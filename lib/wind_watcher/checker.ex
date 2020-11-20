defmodule WindWatcher.Checker do
  use GenServer
  require Logger
  alias WindWatcher.Parser
  alias WindWatcher.Parser.Weather
  alias WindWatcher.Sensor

  defmodule State do
    @enforce_keys [:sensor, :coordinates, :api_key, :interval, :window, :threshold]
    defstruct(
      sensor: nil,
      coordinates: [nil, nil],
      api_key: nil,
      interval: nil,
      window: nil,
      threshold: nil
    )

    # How often to check (in milliseconds).
    # Default: 5 minutes.
    # Be careful reducing this too low, or you may encounter API rate limiting.
    @default_interval 5 * 60 * 1000
    # How far into the future to consider (in milliseconds).
    # Default: 3 hours.
    @default_window 3 * 3600 * 1000
    # How much wind is too much? (in km/h)
    # Default: 20 km/h
    @default_threshold 20

    def from_params(params) when is_list(params), do: Map.new(params) |> from_params()

    def from_params(params) when is_map(params) do
      %__MODULE__{
        sensor: Map.fetch!(params, :sensor),
        coordinates: find(params, :coordinates),
        api_key: find(params, :api_key),
        interval: find(params, :interval, @default_interval),
        window: find(params, :window, @default_window),
        threshold: find(params, :threshold, @default_threshold)
      }
    end

    defp find(params, key, default \\ :err) do
      case Map.get(params, key, Application.get_env(:wind_watcher, :"checker_#{key}", default)) do
        :err -> raise "Must set :checker_#{key} in app config"
        x -> x
      end
    end
  end

  def start_link(params, options) do
    GenServer.start_link(__MODULE__, State.from_params(params), options)
  end

  @impl true
  def init(state) do
    {:ok, state, {:continue, :schedule}}
  end

  @impl true
  def handle_info(:timeout, state) do
    run_check(state)
    {:noreply, state, {:continue, :schedule}}
  end

  @impl true
  def handle_continue(:schedule, state) do
    now = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    remain = state.interval - rem(now, state.interval)
    Logger.debug("Next check in #{remain} ms.")
    {:noreply, state, remain}
  end

  def run_check(state) do
    fetch_weather(state) |> do_check(state)
  end

  defp do_check({:ok, json}, state) do
    cutoff = DateTime.utc_now() |> DateTime.add(state.window, :millisecond)
    speed = max_speed(json, cutoff)
    Logger.info("Maximum forecast wind speed is #{speed} kph.")

    if speed >= state.threshold do
      Logger.info("Wind speed of #{speed} exceeds limit of #{state.threshold} kph.")
      Sensor.alarm(state.sensor)
    else
      Logger.info("Wind speed of #{speed} is within limit of #{state.threshold} kph.")
      Sensor.clear(state.sensor)
    end
  end

  defp do_check({:error, error}, _state) do
    Logger.error("Checker: #{error}")
  end

  defp fetch_weather(state) do
    [latitude, longitude] = state.coordinates

    query =
      URI.encode_query(%{
        lat: latitude,
        lon: longitude,
        appid: state.api_key
      })

    uri = "https://api.openweathermap.org/data/2.5/onecall?#{query}"

    case HTTPoison.get(uri) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %HTTPoison.Response{status_code: code}} ->
        {:error, "Got HTTP #{code} response from OpenWeatherMap"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP failure -- #{inspect(reason)}"}
    end
  end

  defp max_speed(json, cutoff) do
    Parser.parse(json)
    |> take_until_cutoff(cutoff)
    |> log_weathers()
    |> max_wind_speed()
  end

  defp take_until_cutoff(weathers, cutoff) do
    weathers
    |> Enum.take_while(fn
      %Weather{time: :now} -> true
      %Weather{time: t} -> DateTime.compare(t, cutoff) == :lt
    end)
  end

  defp log_weathers(weathers) do
    Enum.each(weathers, fn w -> log_weather(w.time, w.wind_speed) end)
    weathers
  end

  defp log_weather(:now, ws), do: Logger.info("Current wind speed is #{ws} kph.")

  defp log_weather(t, ws) do
    Logger.debug("At #{t}, wind speed will be #{ws} km/h.")
  end

  defp max_wind_speed(weathers) do
    weathers
    |> Enum.map(& &1.wind_speed)
    |> Enum.max()
  end
end

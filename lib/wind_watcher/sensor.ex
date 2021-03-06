defmodule WindWatcher.Sensor do
  use GenServer
  require Logger

  # Check sensor status at least once every minute.
  @interval 60_000

  defmodule State do
    alias State

    @enforce_keys [:clear_file, :alarm_file, :min_clear, :keepalive]
    defstruct(
      clear_file: nil,
      alarm_file: nil,
      min_clear: nil,
      keepalive: nil,
      last_time: nil,
      clear_time: nil,
      last_report: :no_data
    )

    # Minimum time (in milliseconds) we must receive an "all clear" signal
    # continuously in order to truly consider things all clear.
    # Default: 30 minutes.
    @default_min_clear 30 * 60 * 1000
    # Maximum time (in milliseconds) since the last message before we assume
    # something is wrong and consider ourselves in an alarm state.
    # Default: 11 minutes (i.e. two Checker cycles, by default).
    @default_keepalive 11 * 60 * 1000

    def from_params(params) when is_list(params), do: Map.new(params) |> from_params()

    def from_params(params) when is_map(params) do
      %State{
        clear_file: find(params, :clear_file, nil),
        alarm_file: find(params, :alarm_file, nil),
        min_clear: find(params, :min_clear, @default_min_clear),
        keepalive: find(params, :keepalive, @default_keepalive)
      }
    end

    defp find(params, key, default \\ :err) do
      case Map.get(params, key, Application.get_env(:wind_watcher, :"sensor_#{key}", default)) do
        :err -> raise "Must set :sensor_#{key} in app config"
        x -> x
      end
    end

    defp unix_now, do: DateTime.utc_now() |> DateTime.to_unix(:millisecond)

    def set_clear(state) do
      now = unix_now()

      new_clear_time =
        cond do
          # If this is our first message, jump straight to clear status.
          is_nil(state.last_time) -> now
          # If we were in alarm, then clear after `min_clear` milliseconds.
          is_nil(state.clear_time) -> now + state.min_clear
          # Otherwise, keep the same `clear_time`.
          true -> state.clear_time
        end

      %State{state | clear_time: new_clear_time, last_time: now}
    end

    def set_alarm(state) do
      %State{state | clear_time: nil, last_time: unix_now()}
    end

    def is_clear?(state, now \\ unix_now())
    def is_clear?(%State{clear_time: nil}, _now), do: false
    def is_clear?(state, now), do: state.clear_time <= now

    def is_alive?(state, now \\ unix_now())
    def is_alive?(%State{last_time: nil}, _now), do: false
    def is_alive?(state, now), do: state.last_time + state.keepalive >= now

    def check(state) do
      now = unix_now()

      case [is_alive?(state, now), is_clear?(state, now)] do
        [false, _] ->
          report(state, :alarm, :no_data, "no data (alarm)")

        [true, false] ->
          if is_integer(state.clear_time) do
            report(
              state,
              :alarm,
              :pending,
              "alarm (pending clear in #{state.clear_time - now} ms)"
            )
          else
            report(state, :alarm, :alarm, "alarm")
          end

        [true, true] ->
          report(state, :clear, :clear, "all clear")
      end
    end

    defp report(state, code, report, message) do
      if report != state.last_report do
        Logger.notice("Sensor status changed: #{message}.")
      else
        Logger.debug("Sensor status: #{message}.")
      end

      {code, %State{state | last_report: report}}
    end
  end

  def start_link(params, options) do
    GenServer.start_link(__MODULE__, State.from_params(params), options)
  end

  def clear(pid), do: GenServer.cast(pid, :clear)
  def alarm(pid), do: GenServer.cast(pid, :alarm)

  @impl true
  def init(state) do
    # Try touching the files to make sure we can write to it.
    touch!(state.clear_file)
    rm_f!(state.clear_file)
    touch!(state.alarm_file)
    rm_f!(state.alarm_file)
    {:ok, state, {:continue, :check}}
  end

  @impl true
  def handle_cast(:clear, state) do
    Logger.debug("Sensor received 'clear' message.")
    {:noreply, State.set_clear(state), {:continue, :check}}
  end

  @impl true
  def handle_cast(:alarm, state) do
    Logger.debug("Sensor received 'alarm' message.")
    {:noreply, State.set_alarm(state), {:continue, :check}}
  end

  @impl true
  def handle_info(:timeout, state) do
    {:noreply, state, {:continue, :check}}
  end

  @impl true
  def handle_continue(:check, state) do
    {code, new_state} = State.check(state)

    case code do
      :alarm ->
        rm_f!(state.clear_file)
        touch!(state.alarm_file)

      :clear ->
        rm_f!(state.alarm_file)
        touch!(state.clear_file)
    end

    {:noreply, new_state, @interval}
  end

  defp touch!(nil), do: :ok
  defp touch!(file), do: File.touch!(file)

  defp rm_f!(nil), do: :ok

  defp rm_f!(file) do
    case File.rm(file) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      e -> raise "File.rm(#{inspect(file)}) returned #{inspect(e)}"
    end
  end
end

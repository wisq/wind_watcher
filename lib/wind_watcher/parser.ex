defmodule WindWatcher.Parser do
  defmodule Weather do
    @enforce_keys [:time, :wind_speed]
    defstruct(@enforce_keys)
  end

  def parse(json) do
    Poison.decode!(json)
    |> parse_map()
  end

  defp parse_map(map) do
    current = Map.fetch!(map, "current") |> to_weather(:now)
    hourly = Map.fetch!(map, "hourly") |> Enum.map(&to_weather/1)

    [current] ++ hourly
  end

  defp to_weather(map) do
    time = Map.fetch!(map, "dt") |> DateTime.from_unix!()
    to_weather(map, time)
  end

  defp to_weather(map, time) do
    %Weather{
      time: time,
      wind_speed: Map.fetch!(map, "wind_speed") |> ms_to_kph()
    }
  end

  defp ms_to_kph(ms) do
    (ms * 3.6)
    |> Float.round(3)
  end
end

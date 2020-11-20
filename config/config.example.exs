import Config

config :wind_watcher,
  # Touch this file when the wind is low enough.
  sensor_clear_file: "/path/to/clear.file",
  # Touch this file when the wind is too high.
  sensor_alarm_file: "/path/to/alarm.file",
  # (You can omit either of these.)
  #
  # Use negatives for southern latitude or western longitude.
  checker_coordinates: [45.4215, -75.6972],
  # Either stick your API key here, or pull it from the environment.
  checker_api_key: System.get_env("OWM_API_KEY")

config :logger, :console,
  level: :debug,
  format: "$metadata[$level] $levelpad$message\n"

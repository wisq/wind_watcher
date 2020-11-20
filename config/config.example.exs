import Config

config :wind_watcher,
  # Touch this file when the wind is low enough.
  # (That way, if the program crashes, the file will get too old,
  # and homebridge-filesensor will stop accepting it.)
  sensor_file: "/path/to/flag.file",
  # Use negatives for southern latitude or western longitude.
  checker_coordinates: [45.4215, -75.6972],
  # Either stick your API key here, or pull it from the environment.
  checker_api_key: System.get_env("OWM_API_KEY")

config :logger, :console,
  level: :debug,
  format: "$metadata[$level] $levelpad$message\n"

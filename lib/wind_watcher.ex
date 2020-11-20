defmodule WindWatcher do
  use Application
  require Logger

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    children =
      if supervise?() do
        Logger.info("WindWatcher starting ...")
        child_specs()
      else
        []
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WindWatcher.Supervisor]

    Supervisor.start_link(children, opts)
  end

  def supervise? do
    !iex_running?()
  end

  defp iex_running? do
    Code.ensure_loaded?(IEx) and IEx.started?()
  end

  defp child_specs() do
    sensor_id = :ww_sensor
    checker_id = :ww_checker

    sensor_spec = %{
      id: sensor_id,
      start: {WindWatcher.Sensor, :start_link, [[], [name: sensor_id]]}
    }

    checker_spec = %{
      id: checker_id,
      start: {WindWatcher.Checker, :start_link, [[sensor: sensor_id], [name: checker_id]]}
    }

    [sensor_spec, checker_spec]
  end
end

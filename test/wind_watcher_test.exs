defmodule WindWatcherTest do
  use ExUnit.Case
  doctest WindWatcher

  test "greets the world" do
    assert WindWatcher.hello() == :world
  end
end

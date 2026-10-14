defmodule Mini.Runtime do
  @moduledoc "Builtin functions callable from Mini programs."

  def print(args) do
    args |> Enum.map(&show/1) |> Enum.join(" ") |> IO.puts()
    nil
  end

  def concat(args), do: args |> Enum.map(&show/1) |> Enum.join()

  def str([value]), do: show(value)

  def show(nil), do: "nil"
  def show(value) when is_binary(value), do: value
  def show(value), do: to_string(value)
end

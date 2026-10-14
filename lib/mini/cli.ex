defmodule Mini.CLI do
  @moduledoc false

  @usage """
  usage: mini <command> file.mini

  commands:
    run     compile and run main()
    build   write mini_<name>.beam to the current directory
    erl     print the generated code as Erlang source
    ast     print the parsed AST
  """

  def main([cmd, file]) when cmd in ~w(run build erl ast) do
    source = File.read!(file)
    name = file |> Path.basename(".mini") |> String.replace(~r/[^a-zA-Z0-9_]/, "_")

    case command(cmd, source, name) do
      :ok -> :ok
      {:error, msg, pos} -> die(Mini.format_error(file, msg, pos))
      {:runtime_error, msg} -> die("#{file}: runtime error: #{msg}")
    end
  end

  def main(_) do
    IO.puts(:stderr, @usage)
    System.halt(2)
  end

  defp command("run", source, name) do
    with {:ok, _value} <- Mini.run(source, name), do: :ok
  end

  defp command("build", source, name) do
    with {:ok, module, beam} <- Mini.compile(source, name) do
      File.write!("#{module}.beam", beam)
      IO.puts("wrote #{module}.beam (builtins need Mini.Runtime on the code path)")
    end
  end

  defp command("erl", source, name) do
    with {:ok, code} <- Mini.to_erlang(source, name), do: IO.puts(code)
  end

  defp command("ast", source, _name) do
    with {:ok, ast} <- Mini.parse(source), do: IO.inspect(ast, pretty: true, limit: :infinity)
  end

  defp die(msg) do
    IO.puts(:stderr, msg)
    System.halt(1)
  end
end

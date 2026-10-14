defmodule Mini do
  @moduledoc """
  Mini: a small expression-oriented language compiled to BEAM bytecode.

      source -> Lexer -> Parser -> Checker -> Codegen -> :compile.forms -> .beam
  """

  alias Mini.{Lexer, Parser, Checker, Codegen}

  @type error :: {:error, String.t(), {pos_integer, pos_integer}}

  @doc "Parses source into an AST."
  def parse(source) do
    with {:ok, tokens} <- Lexer.tokenize(source),
         {:ok, ast} <- Parser.parse(tokens),
         :ok <- Checker.check(ast) do
      {:ok, ast}
    end
  end

  @doc "Returns the generated Erlang abstract forms."
  def to_forms(source, name \\ "main") do
    with {:ok, ast} <- parse(source), do: {:ok, Codegen.generate(ast, name)}
  end

  @doc "Pretty prints the generated code as Erlang source."
  def to_erlang(source, name \\ "main") do
    with {:ok, {_mod, forms}} <- to_forms(source, name) do
      {:ok, forms |> Enum.map(&:erl_pp.form/1) |> IO.iodata_to_binary()}
    end
  end

  @doc "Compiles source into `{module, beam_binary}`."
  def compile(source, name \\ "main") do
    with {:ok, {_mod, forms}} <- to_forms(source, name) do
      case :compile.forms(forms, [:binary, :return_errors]) do
        {:ok, module, beam} -> {:ok, module, beam}
        {:ok, module, beam, _warnings} -> {:ok, module, beam}
        {:error, errors, _warnings} -> {:error, "Erlang compiler: #{inspect(errors)}", {1, 1}}
      end
    end
  end

  @doc "Compiles, loads and runs `main()`, returning its value."
  def run(source, name \\ "main") do
    with {:ok, module, beam} <- compile(source, name) do
      {:module, ^module} = :code.load_binary(module, ~c"#{name}.mini", beam)

      try do
        {:ok, module.main()}
      rescue
        e in ArithmeticError -> {:runtime_error, "arithmetic on a non-number, or division by zero (#{Exception.message(e)})"}
        e in CaseClauseError -> {:runtime_error, "`if` condition must be true or false, got #{inspect(e.term)}"}
        e -> {:runtime_error, Exception.message(e)}
      end
    end
  end

  def format_error(file, msg, {line, col}), do: "#{file}:#{line}:#{col}: error: #{msg}"
end

defmodule Mini.Checker do
  @moduledoc """
  Static checks run before code generation:

    * every function name is unique and `main()` exists
    * every called function exists with the right number of arguments
    * every variable is bound before it is used (`let` is block scoped)
  """

  @builtins %{"print" => :any, "concat" => :any, "str" => 1}

  def builtins, do: @builtins

  def check({:program, functions}) do
    arities =
      Enum.reduce(functions, %{}, fn {:fn, pos, name, params, _}, acc ->
        cond do
          Map.has_key?(acc, name) -> fail("function `#{name}` is defined twice", pos)
          Map.has_key?(@builtins, name) -> fail("`#{name}` is a builtin and cannot be redefined", pos)
          true -> Map.put(acc, name, length(params))
        end
      end)

    if Map.get(arities, "main") != 0, do: fail("program needs a `fn main()` with no parameters", {1, 1})

    for {:fn, pos, _name, params, body} <- functions do
      if length(Enum.uniq(params)) != length(params), do: fail("duplicate parameter name", pos)
      expr(body, MapSet.new(params), arities)
    end

    :ok
  catch
    {:check_error, msg, pos} -> {:error, msg, pos}
  end

  defp expr({:block, _, stmts}, scope, funs) do
    Enum.reduce(stmts, scope, fn
      {:let, _, name, value}, scope ->
        expr(value, scope, funs)
        MapSet.put(scope, name)

      e, scope ->
        expr(e, scope, funs)
        scope
    end)
  end

  defp expr({:var, pos, name}, scope, _funs) do
    unless MapSet.member?(scope, name), do: fail("undefined variable `#{name}`", pos)
  end

  defp expr({:call, pos, name, args}, scope, funs) do
    expected = Map.get(funs, name) || Map.get(@builtins, name)

    cond do
      expected == nil -> fail("undefined function `#{name}`", pos)
      expected != :any and expected != length(args) ->
        fail("`#{name}` takes #{expected} argument(s), got #{length(args)}", pos)
      true -> Enum.each(args, &expr(&1, scope, funs))
    end
  end

  defp expr({:if, _, c, t, e}, scope, funs), do: Enum.each([c, t, e], &expr(&1, scope, funs))
  defp expr({:binop, _, _, l, r}, scope, funs), do: Enum.each([l, r], &expr(&1, scope, funs))
  defp expr({op, _, e}, scope, funs) when op in [:neg, :not], do: expr(e, scope, funs)
  defp expr({lit, _, _}, _scope, _funs) when lit in [:int, :string, :bool], do: :ok

  defp fail(msg, pos), do: throw({:check_error, msg, pos})
end

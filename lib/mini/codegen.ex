defmodule Mini.Codegen do
  @moduledoc """
  Translates the Mini AST into Erlang abstract format, which the stock Erlang
  compiler turns into BEAM bytecode.

  Erlang variables can only be bound once, so every `let` gets a fresh Erlang
  variable (`x` -> `X@1`, `X@2`, ...) and the environment maps Mini names to
  their latest Erlang variable.
  """

  @ops %{
    +: :+, -: :-, *: :*, /: :div, %: :rem,
    ==: :"=:=", !=: :"=/=", <: :<, >: :>, <=: :"=<", >=: :>=,
    and: :andalso, or: :orelse
  }

  def module_name(name), do: :"mini_#{name}"

  def generate({:program, functions}, name) do
    module = module_name(name)
    exports = for {:fn, _, fname, params, _} <- functions, do: {String.to_atom(fname), length(params)}

    forms =
      [
        {:attribute, 1, :file, {~c"#{name}.mini", 1}},
        {:attribute, 1, :module, module},
        {:attribute, 1, :export, exports}
      ] ++ Enum.map(functions, &function/1) ++ [{:eof, 1}]

    {module, forms}
  end

  defp function({:fn, {line, _}, name, params, body}) do
    {vars, env} =
      Enum.map_reduce(params, %{}, fn p, env ->
        {var, env} = fresh(env, p, line)
        {var, env}
      end)

    {exprs, _env} = block(body, env)
    {:function, line, String.to_atom(name), length(params), [{:clause, line, vars, [], exprs}]}
  end

  # Returns a non-empty list of Erlang expressions; the last one is the value.
  defp block({:block, {line, _}, stmts}, env) do
    {exprs, env} =
      Enum.map_reduce(stmts, env, fn
        {:let, {l, _}, name, value}, env ->
          value = expr(value, env)
          {var, env} = fresh(env, name, l)
          {{:match, l, var, value}, env}

        e, env ->
          {expr(e, env), env}
      end)

    exprs =
      case List.last(stmts) do
        nil -> [{:atom, line, nil}]
        {:let, _, _, _} -> exprs ++ [{:atom, line, nil}]
        _ -> exprs
      end

    {exprs, env}
  end

  defp expr({:int, {l, _}, n}, _env), do: {:integer, l, n}
  defp expr({:bool, {l, _}, b}, _env), do: {:atom, l, b}

  defp expr({:string, {l, _}, s}, _env),
    do: {:bin, l, [{:bin_element, l, {:string, l, String.to_charlist(s)}, :default, [:utf8]}]}

  defp expr({:var, {l, _}, name}, env), do: {:var, l, Map.fetch!(env.vars, name)}
  defp expr({:neg, {l, _}, e}, env), do: {:op, l, :-, expr(e, env)}
  defp expr({:not, {l, _}, e}, env), do: {:op, l, :not, expr(e, env)}
  defp expr({:binop, {l, _}, op, a, b}, env), do: {:op, l, Map.fetch!(@ops, op), expr(a, env), expr(b, env)}

  defp expr({:if, {l, _}, c, t, e}, env) do
    # Branches get their own scope: bindings inside them never leak out.
    {then_exprs, _} = block(t, env)
    {else_exprs, _} = block(e, env)

    {:case, l, expr(c, env),
     [
       {:clause, l, [{:atom, l, true}], [], then_exprs},
       {:clause, l, [{:atom, l, false}], [], else_exprs}
     ]}
  end

  defp expr({:call, {l, _}, name, args}, env) do
    args = Enum.map(args, &expr(&1, env))

    if Map.has_key?(Mini.Checker.builtins(), name) do
      # builtins live in Mini.Runtime and take their arguments as one list
      runtime = {:remote, l, {:atom, l, Mini.Runtime}, {:atom, l, String.to_atom(name)}}
      {:call, l, runtime, [list(args, l)]}
    else
      {:call, l, {:atom, l, String.to_atom(name)}, args}
    end
  end

  defp list([], l), do: {nil, l}
  defp list([h | t], l), do: {:cons, l, h, list(t, l)}

  defp fresh(env, name, line) do
    env = Map.merge(%{vars: %{}, counter: 0}, env)
    n = env.counter + 1
    var = :"#{String.capitalize(name)}@#{n}"
    {{:var, line, var}, %{env | counter: n, vars: Map.put(env.vars, name, var)}}
  end
end

defmodule Mini.Parser do
  @moduledoc """
  Recursive descent parser with Pratt-style precedence climbing for expressions.

  Grammar:

      program   = function*
      function  = "fn" IDENT "(" params? ")" block
      block     = "{" (statement ";")* expr? "}"
      statement = "let" IDENT "=" expr | expr
      expr      = if | binary
      if        = "if" expr block ("else" (if | block))?
      primary   = INT | STRING | true | false | IDENT | IDENT "(" args? ")"
                | "(" expr ")" | ("-" | "!" | "not") primary

  AST nodes are tuples whose second element is the `{line, col}` position.
  """

  # {left binding power, AST operator}
  @binary %{
    or: {1, :or}, "||": {1, :or},
    and: {2, :and}, "&&": {2, :and},
    "==": {3, :==}, "!=": {3, :!=},
    <: {4, :<}, >: {4, :>}, <=: {4, :<=}, >=: {4, :>=},
    +: {5, :+}, -: {5, :-},
    *: {6, :*}, /: {6, :/}, %: {6, :%}
  }

  def parse(tokens) do
    {functions, [{:eof, _, _}]} = many_functions(tokens, [])
    {:ok, {:program, functions}}
  catch
    {:parse_error, msg, pos} -> {:error, msg, pos}
  end

  defp many_functions([{:eof, _, _}] = rest, acc), do: {Enum.reverse(acc), rest}
  defp many_functions(tokens, acc) do
    {fun, rest} = function(tokens)
    many_functions(rest, [fun | acc])
  end

  defp function([{:fn, _, pos} | rest]) do
    {name, rest} = expect(rest, :ident)
    rest = expect!(rest, :"(")
    {params, rest} = comma_list(rest, :")", fn toks -> expect(toks, :ident) end)
    {body, rest} = block(rest)
    {{:fn, pos, name, params, body}, rest}
  end

  defp function([{_, _, pos} | _]), do: fail("expected `fn`", pos)

  defp block(tokens) do
    {_, _, pos} = hd(tokens)
    rest = expect!(tokens, :"{")
    {stmts, rest} = statements(rest, [])
    {{:block, pos, stmts}, rest}
  end

  # A block is a list of statements; the value of the last expression is the block's value.
  defp statements([{:"}", _, _} | rest], acc), do: {Enum.reverse(acc), rest}

  defp statements([{:let, _, pos} | rest], acc) do
    {name, rest} = expect(rest, :ident)
    rest = expect!(rest, :=)
    {value, rest} = expr(rest, 0)
    rest = expect!(rest, :";")
    statements(rest, [{:let, pos, name, value} | acc])
  end

  defp statements(tokens, acc) do
    {e, rest} = expr(tokens, 0)

    case rest do
      [{:";", _, _} | rest] -> statements(rest, [e | acc])
      [{:"}", _, _} | rest] -> {Enum.reverse([e | acc]), rest}
      [{_, _, pos} | _] -> fail("expected `;` or `}`", pos)
    end
  end

  defp expr([{:if, _, pos} | rest], _min_bp) do
    {cond, rest} = expr(rest, 0)
    {then, rest} = block(rest)

    case rest do
      [{:else, _, _}, {:if, _, _} | _] = [_ | rest] ->
        {else_if, rest} = expr(rest, 0)
        {{:if, pos, cond, then, {:block, pos, [else_if]}}, rest}

      [{:else, _, _} | rest] ->
        {otherwise, rest} = block(rest)
        {{:if, pos, cond, then, otherwise}, rest}

      _ ->
        {{:if, pos, cond, then, {:block, pos, []}}, rest}
    end
  end

  defp expr(tokens, min_bp) do
    {left, rest} = prefix(tokens)
    infix(left, rest, min_bp)
  end

  defp infix(left, [{op, _, pos} | rest] = tokens, min_bp) do
    case Map.get(@binary, op) do
      {bp, ast_op} when bp > min_bp ->
        {right, rest} = expr(rest, bp)
        infix({:binop, pos, ast_op, left, right}, rest, min_bp)

      _ ->
        {left, tokens}
    end
  end

  defp prefix([{:int, n, pos} | rest]), do: {{:int, pos, n}, rest}
  defp prefix([{:string, s, pos} | rest]), do: {{:string, pos, s}, rest}
  defp prefix([{true, _, pos} | rest]), do: {{:bool, pos, true}, rest}
  defp prefix([{false, _, pos} | rest]), do: {{:bool, pos, false}, rest}

  defp prefix([{:ident, name, pos}, {:"(", _, _} | rest]) do
    {args, rest} = comma_list(rest, :")", &expr(&1, 0))
    {{:call, pos, name, args}, rest}
  end

  defp prefix([{:ident, name, pos} | rest]), do: {{:var, pos, name}, rest}

  defp prefix([{:"(", _, _} | rest]) do
    {e, rest} = expr(rest, 0)
    {e, expect!(rest, :")")}
  end

  defp prefix([{:-, _, pos} | rest]) do
    {e, rest} = expr(rest, 6)
    {{:neg, pos, e}, rest}
  end

  defp prefix([{op, _, pos} | rest]) when op in [:!, :not] do
    {e, rest} = expr(rest, 6)
    {{:not, pos, e}, rest}
  end

  defp prefix([{:if, _, _} | _] = tokens), do: expr(tokens, 0)
  defp prefix([{:eof, _, pos} | _]), do: fail("unexpected end of file", pos)
  defp prefix([{type, value, pos} | _]), do: fail("unexpected #{describe(type, value)}", pos)

  # Parses `item, item, ...` up to (and including) the closing token.
  defp comma_list([{close, _, _} | rest], close, _item), do: {[], rest}

  defp comma_list(tokens, close, item) do
    {first, rest} = item.(tokens)

    case rest do
      [{:",", _, _} | rest] ->
        {more, rest} = comma_list(rest, close, item)
        {[first | more], rest}

      [{^close, _, _} | rest] ->
        {[first], rest}

      [{type, value, pos} | _] ->
        fail("expected `,` or `#{close}`, got #{describe(type, value)}", pos)
    end
  end

  defp expect([{type, value, _} | rest], type), do: {value, rest}
  defp expect([{t, v, pos} | _], type), do: fail("expected #{type}, got #{describe(t, v)}", pos)

  defp expect!(tokens, type) do
    {_, rest} = expect(tokens, type)
    rest
  end

  defp describe(:eof, _), do: "end of file"
  defp describe(:ident, name), do: "identifier `#{name}`"
  defp describe(:int, n), do: "number #{n}"
  defp describe(:string, _), do: "string"
  defp describe(type, _), do: "`#{type}`"

  defp fail(msg, pos), do: throw({:parse_error, msg, pos})
end

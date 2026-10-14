defmodule Mini.Lexer do
  @moduledoc "Turns source text into a list of `{type, value, {line, col}}` tokens."

  @keywords ~w(fn let if else true false and or not)
  @symbols ~w[== != <= >= && || + - * / % < > = ( ) { } , ; !]

  def tokenize(source), do: lex(String.to_charlist(source), 1, 1, [])

  defp lex([], line, col, acc), do: {:ok, Enum.reverse([{:eof, nil, {line, col}} | acc])}

  defp lex([?\n | rest], line, _col, acc), do: lex(rest, line + 1, 1, acc)
  defp lex([c | rest], line, col, acc) when c in [?\s, ?\t, ?\r], do: lex(rest, line, col + 1, acc)

  # comments run to end of line
  defp lex([?/, ?/ | rest], line, _col, acc) do
    rest = Enum.drop_while(rest, &(&1 != ?\n))
    lex(rest, line, 1, acc)
  end

  defp lex([c | _] = chars, line, col, acc) when c in ?0..?9 do
    {digits, rest} = Enum.split_while(chars, &(&1 in ?0..?9 or &1 == ?_))
    value = digits |> Enum.reject(&(&1 == ?_)) |> List.to_integer()
    lex(rest, line, col + length(digits), [{:int, value, {line, col}} | acc])
  end

  defp lex([c | _] = chars, line, col, acc) when c in ?a..?z or c in ?A..?Z or c == ?_ do
    {word, rest} = Enum.split_while(chars, &(&1 in ?a..?z or &1 in ?A..?Z or &1 in ?0..?9 or &1 == ?_))
    word = List.to_string(word)

    token =
      if word in @keywords,
        do: {String.to_atom(word), nil, {line, col}},
        else: {:ident, word, {line, col}}

    lex(rest, line, col + String.length(word), [token | acc])
  end

  defp lex([?" | rest], line, col, acc) do
    case read_string(rest, []) do
      {:ok, str, consumed, rest} -> lex(rest, line, col + consumed + 2, [{:string, str, {line, col}} | acc])
      :error -> {:error, "unterminated string", {line, col}}
    end
  end

  defp lex(chars, line, col, acc) do
    case Enum.find(@symbols, &List.starts_with?(chars, String.to_charlist(&1))) do
      nil ->
        {:error, "unexpected character #{inspect(<<hd(chars)::utf8>>)}", {line, col}}

      sym ->
        n = byte_size(sym)
        lex(Enum.drop(chars, n), line, col + n, [{String.to_atom(sym), nil, {line, col}} | acc])
    end
  end

  defp read_string(chars, acc, consumed \\ 0)
  defp read_string([], _acc, _consumed), do: :error
  defp read_string([?\n | _], _acc, _consumed), do: :error
  defp read_string([?" | rest], acc, consumed), do: {:ok, acc |> Enum.reverse() |> List.to_string(), consumed, rest}
  defp read_string([?\\, ?n | rest], acc, n), do: read_string(rest, [?\n | acc], n + 2)
  defp read_string([?\\, ?t | rest], acc, n), do: read_string(rest, [?\t | acc], n + 2)
  defp read_string([?\\, c | rest], acc, n), do: read_string(rest, [c | acc], n + 2)
  defp read_string([c | rest], acc, n), do: read_string(rest, [c | acc], n + 1)
end

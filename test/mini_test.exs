defmodule MiniTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  defp run(src), do: Mini.run(src, "t#{System.unique_integer([:positive])}")
  defp value(src), do: elem(run(src), 1)

  test "arithmetic and precedence" do
    assert value("fn main() { 1 + 2 * 3 - 4 / 2 }") == 5
    assert value("fn main() { (1 + 2) * 3 }") == 9
    assert value("fn main() { -7 % 3 }") == -1
    assert value("fn main() { --5 }") == 5
  end

  test "comparisons and logic" do
    assert value("fn main() { 1 < 2 and 2 <= 2 and not (3 == 4) }") == true
    assert value("fn main() { 1 != 1 || false }") == false
  end

  test "let shadowing is single-assignment safe" do
    assert value("fn main() { let x = 1; let x = x + 1; let x = x * 10; x }") == 20
  end

  test "if is an expression and its bindings are scoped" do
    src = """
    fn main() {
      let x = 1;
      let y = if x == 1 { let x = 100; x + 1 } else { 0 };
      x + y
    }
    """

    assert value(src) == 102
  end

  test "else if chains" do
    src = "fn sign(n) { if n < 0 { -1 } else if n == 0 { 0 } else { 1 } } fn main() { sign(-5) + sign(0) * 10 + sign(9) * 100 }"
    assert value(src) == 99
  end

  test "recursion, including deep tail recursion" do
    assert value("fn f(n) { if n < 2 { n } else { f(n - 1) + f(n - 2) } } fn main() { f(20) }") == 6765
    assert value("fn loop(n, acc) { if n == 0 { acc } else { loop(n - 1, acc + n) } } fn main() { loop(1000000, 0) }") ==
             500_000_500_000
  end

  test "builtins" do
    assert capture_io(fn -> run(~S|fn main() { print("a", 1, true, concat("x", 2)); }|) end) == "a 1 true x2\n"
    assert value(~S|fn main() { concat("n=", 4 * 4) }|) == "n=16"
    assert value(~S|fn main() { str(12) }|) == "12"
  end

  test "empty blocks and trailing let evaluate to nil" do
    assert value("fn main() { }") == nil
    assert value("fn main() { let a = 1; }") == nil
  end

  test "static errors carry positions" do
    assert {:error, "undefined variable `y`", {1, 17}} = run("fn main() { 1 + y }")
    assert {:error, "undefined function `nope`", {1, 13}} = run("fn main() { nope() }")
    assert {:error, "`f` takes 1 argument(s), got 2", _} = run("fn f(a) { a } fn main() { f(1, 2) }")
    assert {:error, "program needs a `fn main()` with no parameters", _} = run("fn f() { 1 }")
    assert {:error, "function `f` is defined twice", _} = run("fn f() { 1 } fn f() { 2 } fn main() { }")
    assert {:error, "expected `;` or `}`", {1, 15}} = run("fn main() { 1 2 }")
    assert {:error, "unterminated string", _} = run(~S|fn main() { "abc }|)
    assert {:error, "unexpected character \"@\"", {1, 13}} = run("fn main() { @ }")
  end

  test "runtime errors are reported, not crashes" do
    assert {:runtime_error, msg} = run("fn main() { 1 / 0 }")
    assert msg =~ "division by zero"
    assert {:runtime_error, msg} = run("fn main() { if 1 { 2 } else { 3 } }")
    assert msg =~ "must be true or false"
  end

  test "generated Erlang is readable" do
    {:ok, erl} = Mini.to_erlang("fn add(a, b) { a + b } fn main() { add(1, 2) }", "demo")
    assert erl =~ "-module(mini_demo)."
    assert erl =~ ~r"add\(A@1, B@2\) ->\s+A@1 \+ B@2\."
  end

  test "examples compile" do
    for file <- Path.wildcard("examples/*.mini") do
      assert {:ok, _, _} = Mini.compile(File.read!(file), Path.basename(file, ".mini")), file
    end
  end
end

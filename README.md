# Compiler
My own compiler implementation in elixir.
# rules
Make it work
Make it beautiful
Make it efficient

## Mini
**Mini** is a small expression-oriented language that compiles to native BEAM bytecode:

```
source ─► Lexer ─► Parser (Pratt) ─► Checker ─► Codegen ─► Erlang abstract format ─► :compile.forms ─► .beam
```

```
fn fib(n) {
  if n < 2 { n } else { fib(n - 1) + fib(n - 2) }
}

fn main() {
  let n = 25;
  print(concat("fib(", n, ") ="), fib(n));
}
```

Language:
- integers, booleans, strings; `+ - * / %` (integer division), `== != < > <= >=`, `and or not` (also `&& || !`)
- `let` bindings (shadowing allowed, block scoped), `if / else if / else` as expressions, blocks evaluate to their last expression
- functions with recursion; tail calls run in constant stack (it's the BEAM)
- builtins: `print(...)`, `concat(...)`, `str(x)`
- static checks with `line:col` errors: undefined variables/functions, wrong arity, duplicate definitions, missing `main()`
- runtime errors (division by zero, non-boolean `if` condition) are reported cleanly

Since BEAM variables are single-assignment, codegen renames every binding (`x` → `X@1`, `X@2`, …). See what it produces with `mini erl`.

## Usage
```sh
mix escript.build
./mini run examples/fib.mini     # compile + run main()
./mini erl examples/fib.mini     # show the generated Erlang
./mini ast examples/fib.mini     # show the AST
./mini build examples/fib.mini   # write mini_fib.beam
mix test
```

| File | Stage |
| --- | --- |
| `lib/mini/lexer.ex` | source → tokens with positions |
| `lib/mini/parser.ex` | tokens → AST (recursive descent + precedence climbing) |
| `lib/mini/checker.ex` | scope/arity checks |
| `lib/mini/codegen.ex` | AST → Erlang abstract forms |
| `lib/mini.ex` | pipeline, compile + load + run |
| `lib/mini/runtime.ex` | builtins |

Next ideas: lists and pattern matching, closures, a type checker, an own bytecode backend instead of the Erlang compiler.

# Statex

Process-agnostic finite state machines as plain data for Elixir.

`Statex` lets you define, validate, and drive finite state machines using
plain functions and structs — no macros, no processes, no magic. Definitions
are validated at **compile time**, and because everything is a plain struct,
you can inspect, serialize, and generate Mermaid diagrams from your machines
without any extra tooling.

## Features

- **No macros** — definitions and instances are plain `%Statex.Definition{}`
  and `%Statex.Instance{}` structs built with ordinary functions.
- **Compile-time validation** — assign the definition to a `@machine` module
  attribute; `mix compile` catches invalid machines before they reach production.
- **Process-agnostic** — call `transition/3` from a `GenServer`, a LiveView,
  an Oban job, or a plain script.
- **Hooks** — per-state `entry`/`exit` and per-transition `action` functions
  thread updated data through each step.
- **Guards** — multiple transitions on the same `{state, event}` pair with
  first-match-wins resolution.
- **Mermaid diagrams** — generate `stateDiagram-v2` diagrams directly from a
  definition with `Statex.to_mermaid/2`.
- **Zero runtime dependencies**.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `statex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:statex, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/statex>.

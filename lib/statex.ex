defmodule Statex do
  @moduledoc """
  Process-agnostic finite state machines as plain data.

  `Statex` is a data-first FSM library with no macros. State machine
  definitions are built with plain functions, validated at compile time,
  and driven by calling `transition/3` on an instance value — no process,
  no `GenServer`, no magic.

  ## Quickstart

      defmodule TrafficLight do
        @machine Statex.define()
                 |> Statex.add_state(:red, initial: true)
                 |> Statex.add_state(:green)
                 |> Statex.add_state(:yellow)
                 |> Statex.add_transition(:red, :go, :green)
                 |> Statex.add_transition(:green, :slow, :yellow)
                 |> Statex.add_transition(:yellow, :stop, :red)
                 |> Statex.compile!()

        def definition, do: @machine
      end

      {:ok, light} = Statex.new(TrafficLight.definition(), %{})
      {:ok, light} = Statex.transition(light, :go)
      light.state  #=> :green
      Statex.to_mermaid(TrafficLight.definition())

  ## Compile-time validation

  Assign the definition to a module attribute and call `Statex.compile!/1`.
  Any invalid definition (unknown states, missing initial, unreachable
  transitions, …) causes the **host module to fail at `mix compile`** rather
  than at runtime.

  ## Function captures inside `@machine`

  Module attributes are evaluated at compile time. Prefer
  `&__MODULE__.fun/3` over `&local_fun/3` so that callback definition
  order does not matter. Because `&__MODULE__.fun/3` becomes an external
  call, the referenced function must be `def`, not `defp`.

  Alternatively, define callbacks above the `@machine` attribute and use
  `&local_fun/3` — private (`defp`) functions work fine with local captures.

  ## Hook execution order

  For a transition `A --event--> B`:

  1. `exit(A).(instance, event, payload)` — may update extended data
  2. transition `action.(instance, event, payload)` — may update extended data
  3. `instance.state` flips to `B`
  4. `entry(B).(instance, event, payload)` — may update extended data

  Each hook receives the instance with data as updated by the previous step.
  On any `{:error, reason}` the chain short-circuits and the **original**
  instance is preserved.

  Self-transitions (`A → A`) are external: both `exit(A)` and `entry(A)` fire.

  ## Internal structure

  Transitions are stored directly on their `from` state, keyed by event name,
  as `{to, guard, action}` tuples in declaration order. The `from` and `event`
  are implicit in the position — the state map key and the event map key
  respectively — so they are not duplicated in the tuple.

  The `Statex.Transition` struct is a public, self-describing view: it is never
  stored, only reconstructed at introspection boundaries (e.g. `transitions_from/2`).

  If you hand-assemble a `%Statex.Definition{}` directly, populate
  `%Statex.State{}.transitions` as `%{event => [{to, guard, action}]}`.

  ## Design principles

  - **No macros** — definitions and instances are plain structs.
  - **Process-agnostic** — call `transition/3` from a `GenServer`, a LiveView,
    an Oban job, or a plain script.
  - **Data first** — because definitions are plain data you can inspect,
    serialize, and generate Mermaid diagrams from them without any extra work.
  """

  @type definition :: Statex.Definition.t()
  @type instance :: Statex.Instance.t()
  @type event :: atom()
  @type payload :: term()

  # ---- Definition building ----

  @doc "Creates a new, empty definition. See `Statex.Definition.new/0`."
  defdelegate define(), to: Statex.Definition, as: :new

  @doc "Creates a definition from a declarative map. See `Statex.Definition.new/1`."
  defdelegate define(map), to: Statex.Definition, as: :new

  defdelegate add_state(definition, name), to: Statex.Definition
  defdelegate add_state(definition, name, opts), to: Statex.Definition
  defdelegate add_transition(definition, from, event, to), to: Statex.Definition
  defdelegate add_transition(definition, from, event, to, opts), to: Statex.Definition
  defdelegate compile(definition), to: Statex.Definition
  defdelegate compile!(definition), to: Statex.Definition

  # ---- Instance lifecycle ----

  defdelegate new(definition, data), to: Statex.Instance
  defdelegate new!(definition, data), to: Statex.Instance
  defdelegate transition(instance, event), to: Statex.Instance
  defdelegate transition(instance, event, payload), to: Statex.Instance
  defdelegate transition!(instance, event), to: Statex.Instance
  defdelegate transition!(instance, event, payload), to: Statex.Instance
  defdelegate final?(instance), to: Statex.Instance

  # ---- Introspection ----

  defdelegate events_from(definition_or_instance, state), to: Statex.Introspection
  defdelegate transitions_from(definition_or_instance, state), to: Statex.Introspection
  defdelegate reachable_states(definition), to: Statex.Introspection
  defdelegate unreachable_states(definition), to: Statex.Introspection
  defdelegate to_mermaid(definition), to: Statex.Introspection
  defdelegate to_mermaid(definition, opts), to: Statex.Introspection
end

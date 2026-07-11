defmodule Statex.Definition do
  @moduledoc """
  A state machine definition — the blueprint from which instances are created.

  Build one incrementally with `Statex.define/0`, `Statex.add_state/3`, and
  `Statex.add_transition/5`. Optionally call `Statex.compile!/1` to validate
  it before use.

  `compile!/1` is a **safety net**, not a gate. You can pass any
  `%Statex.Definition{}` directly to `Statex.new/2` without compiling it
  first — useful for generated or dynamically-assembled machines — but
  structural errors will surface at runtime instead of up front.

  ## Compile-time validation (recommended)

  Assign the definition to a module attribute and call `compile!/1`. Any
  structural problem (unknown states, missing initial, bad arity hooks, …)
  causes the **host module to fail compilation**:

      defmodule TrafficLight do
        @machine Statex.define()
                 |> Statex.add_state(:red, initial: true)
                 |> Statex.add_state(:green)
                 |> Statex.add_state(:yellow)
                 |> Statex.add_transition(:red,    :go,   :green)
                 |> Statex.add_transition(:green,  :slow, :yellow)
                 |> Statex.add_transition(:yellow, :stop, :red)
                 |> Statex.compile!()

        def definition, do: @machine
      end

  ## Declaration order

  States must be declared with `add_state/3` before any transition that
  originates from them is added with `add_transition/5`. Attempting to add
  a transition whose `from` state is not yet declared raises `ArgumentError`.

  ## Function captures inside module attributes

  Because module attributes are evaluated at compile time, prefer
  `&__MODULE__.fun/3` over `&local_fun/3` so that callback definition
  order does not matter. `&__MODULE__.fun/3` becomes an external call,
  so the referenced function must be `def`, not `defp`.

  Alternatively, define callbacks above the `@machine` attribute and use
  `&local_fun/3` — private functions work fine with local captures.
  """

  alias Statex.State
  alias Statex.Transition

  @type t :: %__MODULE__{
          states: %{atom() => State.t()},
          initial: atom() | nil
        }

  defstruct states: %{}, initial: nil

  @doc """
  Creates a new, empty definition. Use the pipeline API to add states and
  transitions, then optionally validate with `compile!/1`.

      Statex.define()
      |> Statex.add_state(:idle, initial: true)
      |> Statex.add_state(:running)
      |> Statex.add_transition(:idle, :start, :running)
      |> Statex.compile!()
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Creates a definition from a declarative map.

  Accepted keys:

  - `:initial` — atom naming the initial state
  - `:states` — `%{name => opts}` where opts may include `:final`, `:entry`, `:exit`
  - `:transitions` — list of maps with `:from`, `:event`, `:to`, and optionally
    `:guard` and `:action`

  ## Example

      Statex.define(%{
        initial: :idle,
        states: %{
          idle:    %{},
          running: %{entry: &MyMod.on_enter_running/3}
        },
        transitions: [
          %{from: :idle, event: :start, to: :running, action: &MyMod.on_start/3}
        ]
      })
  """
  @spec new(%{
          optional(:initial) => atom(),
          optional(:states) => %{atom() => map()},
          optional(:transitions) => [map()]
        }) :: t()
  def new(%{} = map) do
    states = Map.get(map, :states, %{})
    transitions = Map.get(map, :transitions, [])
    initial = Map.get(map, :initial)

    definition = %__MODULE__{initial: initial}

    definition =
      Enum.reduce(states, definition, fn {name, opts}, acc ->
        add_state(acc, name, Map.to_list(opts))
      end)

    Enum.reduce(transitions, definition, fn t, acc ->
      opts =
        t
        |> Map.drop([:from, :event, :to])
        |> Map.to_list()

      add_transition(acc, t.from, t.event, t.to, opts)
    end)
  end

  @doc """
  Adds a state to the definition.

  ## Options

  - `:initial` — `boolean()` — marks this as the initial state; sets
    `definition.initial` to `name`
  - `:final` — `boolean()` — marks this as a final state
  - `:entry` — arity-3 function called when this state is entered
  - `:exit` — arity-3 function called when this state is exited

  Hook signature: `(instance :: Statex.Instance.t(), event :: atom() | nil, payload :: term()) ::
  {:ok, new_data} | {:error, reason}`
  """
  @spec add_state(t(), atom(), keyword()) :: t()
  def add_state(%__MODULE__{} = definition, name, opts \\ []) when is_atom(name) do
    {is_initial, opts} = Keyword.pop(opts, :initial, false)
    {is_final, opts} = Keyword.pop(opts, :final, false)

    state = %State{
      name: name,
      final?: is_final,
      entry: Keyword.get(opts, :entry),
      exit: Keyword.get(opts, :exit)
    }

    definition = %{definition | states: Map.put(definition.states, name, state)}

    if is_initial, do: %{definition | initial: name}, else: definition
  end

  @doc """
  Adds a transition to the definition.

  The `from` state must already be declared with `add_state/3` before calling
  this function.

  Transitions within the same `{from, event}` bucket are evaluated in
  declaration order. When multiple transitions share the same `{from, event}`
  pair, the first whose `guard` returns `true` (or the first with no guard)
  is taken.

  ## Options

  - `:guard` — arity-3 predicate: `(instance, event, payload) :: boolean()`
  - `:action` — arity-3 function: `(instance, event, payload) :: {:ok, data} | {:error, reason}`

  ## Raises

  Raises `ArgumentError` if the `from` state has not been declared yet.
  """
  @spec add_transition(t(), atom(), atom(), atom(), keyword()) :: t()
  def add_transition(%__MODULE__{} = definition, from, event, to, opts \\ [])
      when is_atom(from) and is_atom(event) and is_atom(to) do
    state = Map.get(definition.states, from)

    if is_nil(state) do
      raise ArgumentError,
            "cannot add transition from unknown state #{inspect(from)}; " <>
              "call add_state/3 for #{inspect(from)} before adding transitions from it"
    end

    transition = {to, Access.get(opts, :guard), Access.get(opts, :action)}

    updated_state = %{
      state
      | transitions: Map.update(state.transitions, event, [transition], &(&1 ++ [transition]))
    }

    %{definition | states: Map.put(definition.states, from, updated_state)}
  end

  @doc """
  Returns all transitions in the definition as a list of full
  `Statex.Transition` structs, in state-declaration then event-declaration
  order.

  This is a convenience for introspection, serialization, and diagram
  generation. Transitions are not stored in a flat list internally — they live
  on their `from` state keyed by event.
  """
  @spec all_transitions(t()) :: [Transition.t()]
  def all_transitions(%__MODULE__{} = definition) do
    Enum.map(flat_transitions(definition), fn {from, event, to, guard, action} ->
      Transition.from_stored(from, event, {to, guard, action})
    end)
  end

  @doc """
  Validates the definition and returns `{:ok, definition}` or
  `{:error, [reason]}`.

  All validation errors are collected before returning. The definition itself
  is returned unchanged on success — `compile/1` does not transform it.

  ## Validation rules

  1. At least one state must be declared.
  2. Exactly one initial state must be specified.
  3. Every transition's `:to` must refer to a declared state.
  4. No two unguarded transitions may share the same `{from, event}` pair
     (the second would never be reached).
  5. Every `guard`, `action`, `entry`, and `exit` (when not `nil`) must be
     a function of arity 3.

  ## Error reasons

  - `:no_states`
  - `:no_initial`
  - `{:unknown_initial, state}`
  - `{:unknown_state, {:to, state, from_state, event}}`
  - `{:duplicate_unguarded, {from, event}}`
  - `{:bad_arity, {field, value}}`
  """
  @spec compile(t()) :: {:ok, t()} | {:error, [term()]}
  def compile(%__MODULE__{} = definition) do
    case validate(definition) do
      [] -> {:ok, definition}
      errors -> {:error, errors}
    end
  end

  @doc """
  Like `compile/1` but raises `Statex.CompileError` when validation fails.

  Intended for use in module attributes so that invalid machines fail at
  `mix compile`:

      @machine Statex.define()
               |> Statex.add_state(:idle, initial: true)
               |> Statex.compile!()
  """
  @spec compile!(t()) :: t()
  def compile!(%__MODULE__{} = definition) do
    case compile(definition) do
      {:ok, definition} -> definition
      {:error, reasons} -> raise Statex.CompileError, reasons: reasons
    end
  end

  @doc """
  Returns the list of validation errors for a definition, or `[]` if valid.

  Useful when you want to inspect errors programmatically without raising.
  """
  @spec validate(t()) :: [term()]
  def validate(%__MODULE__{} = definition) do
    []
    |> check_states(definition)
    |> check_initial(definition)
    |> check_transition_states(definition)
    |> check_duplicate_unguarded(definition)
    |> check_callables(definition)
  end

  # --- Private validation ---

  defp check_states(errors, %{states: states}) when map_size(states) == 0,
    do: [:no_states | errors]

  defp check_states(errors, _), do: errors

  defp check_initial(errors, %{initial: nil}), do: [:no_initial | errors]

  defp check_initial(errors, %{initial: initial, states: states}) do
    if Map.has_key?(states, initial),
      do: errors,
      else: [{:unknown_initial, initial} | errors]
  end

  defp check_transition_states(errors, %{states: states} = definition) do
    transition_errors =
      definition
      |> flat_transitions()
      |> Enum.reject(fn {_from, _event, to, _guard, _action} -> Map.has_key?(states, to) end)
      |> Enum.map(fn {from, event, to, _guard, _action} ->
        {:unknown_state, {:to, to, from, event}}
      end)

    errors ++ transition_errors
  end

  defp check_duplicate_unguarded(errors, %{states: states}) do
    duplicates =
      Enum.flat_map(states, fn {state_name, state} ->
        state.transitions
        |> Enum.filter(fn {_event, candidates} ->
          Enum.count(candidates, fn {_to, guard, _action} -> is_nil(guard) end) > 1
        end)
        |> Enum.map(fn {event, _candidates} -> {:duplicate_unguarded, {state_name, event}} end)
      end)

    errors ++ duplicates
  end

  defp check_callables(errors, %{states: states} = definition) do
    state_errors =
      Enum.flat_map(states, fn {_name, state} ->
        Enum.flat_map([entry: state.entry, exit: state.exit], &callable_error/1)
      end)

    transition_errors =
      definition
      |> flat_transitions()
      |> Enum.flat_map(fn {_from, _event, _to, guard, action} ->
        Enum.flat_map([guard: guard, action: action], &callable_error/1)
      end)

    errors ++ state_errors ++ transition_errors
  end

  defp callable_error({_label, nil}), do: []
  defp callable_error({_label, fun}) when is_function(fun, 3), do: []
  defp callable_error({label, fun}), do: [{:bad_arity, {label, fun}}]

  # Flattens all transitions from the nested state/event map into a plain list
  # of {from, event, to, guard, action} tuples.
  defp flat_transitions(%__MODULE__{states: states}) do
    Enum.flat_map(states, fn {state_name, state} ->
      Enum.flat_map(state.transitions, fn {event, candidates} ->
        Enum.map(candidates, fn {to, guard, action} -> {state_name, event, to, guard, action} end)
      end)
    end)
  end
end

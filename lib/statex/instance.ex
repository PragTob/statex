defmodule Statex.Instance do
  @moduledoc """
  A live instance of a state machine.

  Holds the current state name and an opaque user-supplied "extended data"
  term. The definition (`Statex.Definition`) is embedded so the instance is
  self-contained and can be passed around without a separate reference.

  ## Creating an instance

      {:ok, machine} = Statex.Instance.new(definition, %{credit: 0})

  `new/2` accepts any `%Statex.Definition{}`. If you want structural errors
  caught early, run `Statex.compile!/1` on the definition first.

  If the initial state has an `entry` hook, it is called during `new/2` with
  `event = nil` and `payload = nil`.

  ## Transition execution order

  For a transition `A --event--> B`:

  1. `exit(A).(instance, event, payload)` — updates extended data
  2. transition `action.(instance, event, payload)` — updates extended data
  3. `instance.state` flips to `B`
  4. `entry(B).(instance, event, payload)` — updates extended data

  Each hook receives the instance with data as updated by the previous hook.
  On any `{:error, reason}`, the chain short-circuits and the **original**
  instance is returned unchanged.

  Self-transitions (`A → A`) are external: both `exit(A)` and `entry(A)` fire.
  """

  alias Statex.Definition
  alias Statex.Transition

  @type t :: %__MODULE__{
          definition: Definition.t(),
          state: atom(),
          data: term()
        }

  @enforce_keys [:definition, :state, :data]
  defstruct [:definition, :state, :data]

  @doc """
  Creates a new instance of the given state machine definition.

  Sets the current state to `definition.initial` and runs that state's
  `entry` hook (if defined) with `event = nil, payload = nil`.

  Accepts any `%Statex.Definition{}`. For early structural validation call
  `Statex.compile!/1` on the definition before passing it here.
  """
  @spec new(Definition.t(), term()) :: {:ok, t()} | {:error, term()}
  def new(%Definition{} = definition, data) do
    instance = %__MODULE__{
      definition: definition,
      state: definition.initial,
      data: data
    }

    initial_state = definition.states[definition.initial]
    run_entry(instance, initial_state, nil, nil)
  end

  @doc """
  Like `new/2` but raises `Statex.TransitionError` if the initial `entry`
  hook fails.
  """
  @spec new!(Definition.t(), term()) :: t()
  def new!(%Definition{} = definition, data) do
    case new(definition, data) do
      {:ok, instance} ->
        instance

      {:error, reason} ->
        raise Statex.TransitionError,
          reason: reason,
          instance: %__MODULE__{definition: definition, state: definition.initial, data: data},
          event: nil,
          payload: nil
    end
  end

  @doc """
  Returns `true` if the current state is marked as a final state.
  """
  @spec final?(t()) :: boolean()
  def final?(%__MODULE__{state: state, definition: definition}),
    do: definition.states[state].final?

  @doc """
  Fires `event` on the instance, returning `{:ok, new_instance}` on success.

  `payload` defaults to `nil` and is forwarded to guards, the transition
  action, and state hooks.

  ## Error reasons

  - `:no_transition` — no transition from the current state for this event
  - `{:guarded, [Statex.Transition.t()]}` — matching transitions exist but
    every guard returned `false`
  - `{:hook_failed, :exit | :action | :entry, inner_reason}` — a hook
    returned `{:error, inner_reason}`

  On error the original instance is returned unchanged.
  """
  @spec transition(t(), atom(), term()) :: {:ok, t()} | {:error, term()}
  def transition(%__MODULE__{} = instance, event, payload \\ nil) when is_atom(event) do
    state_definition = Map.fetch!(instance.definition.states, instance.state)
    candidates = Map.get(state_definition.transitions, event, [])

    if Enum.empty?(candidates) do
      {:error, :no_transition}
    else
      if transition = find_matching_transition(candidates, instance, event, payload) do
        execute_transition(instance, transition, event, payload)
      else
        full_transitions =
          Enum.map(candidates, &Transition.from_stored(instance.state, event, &1))

        {:error, {:guarded, full_transitions}}
      end
    end
  end

  @doc """
  Like `transition/3` but raises `Statex.TransitionError` on failure.
  """
  @spec transition!(t(), atom(), term()) :: t()
  def transition!(%__MODULE__{} = instance, event, payload \\ nil) do
    case transition(instance, event, payload) do
      {:ok, new_instance} ->
        new_instance

      {:error, reason} ->
        raise Statex.TransitionError,
          reason: reason,
          instance: instance,
          event: event,
          payload: payload
    end
  end

  defp find_matching_transition([], _instance, _event, _payload), do: nil

  defp find_matching_transition([transition | rest], instance, event, payload) do
    {_to, guard, _action} = transition

    passes =
      if guard do
        guard.(instance, event, payload)
      else
        true
      end

    if passes do
      transition
    else
      find_matching_transition(rest, instance, event, payload)
    end
  end

  defp execute_transition(original, {to, _guard, action}, event, payload) do
    from_state = original.definition.states[original.state]
    to_state = original.definition.states[to]

    with {:ok, after_exit} <- run_exit(original, from_state, event, payload),
         {:ok, after_action} <- run_action(after_exit, action, event, payload) do
      run_entry(%{after_action | state: to}, to_state, event, payload)
    end
  end

  defp run_exit(instance, %{exit: nil}, _event, _payload), do: {:ok, instance}

  defp run_exit(instance, %{exit: exit_fn}, event, payload) do
    case exit_fn.(instance, event, payload) do
      {:ok, new_data} -> {:ok, %{instance | data: new_data}}
      {:error, reason} -> {:error, {:hook_failed, :exit, reason}}
    end
  end

  defp run_entry(instance, %{entry: nil}, _event, _payload), do: {:ok, instance}

  defp run_entry(instance, %{entry: entry_fn}, event, payload) do
    case entry_fn.(instance, event, payload) do
      {:ok, new_data} -> {:ok, %{instance | data: new_data}}
      {:error, reason} -> {:error, {:hook_failed, :entry, reason}}
    end
  end

  defp run_action(instance, nil, _event, _payload), do: {:ok, instance}

  defp run_action(instance, action_fn, event, payload) do
    case action_fn.(instance, event, payload) do
      {:ok, new_data} -> {:ok, %{instance | data: new_data}}
      {:error, reason} -> {:error, {:hook_failed, :action, reason}}
    end
  end
end

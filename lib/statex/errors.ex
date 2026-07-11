defmodule Statex.CompileError do
  @moduledoc """
  Raised by `Statex.compile!/1` when a state machine definition is invalid.

  The `reasons` field contains a list of all validation failures found.
  """

  defexception [:reasons]

  @impl true
  def message(%{reasons: reasons}) do
    formatted = Enum.map_join(reasons, "\n  - ", &format_reason/1)
    "Invalid state machine definition:\n  - #{formatted}"
  end

  defp format_reason(:no_states),
    do: "the definition must declare at least one state"

  defp format_reason(:no_initial),
    do: "no initial state specified (use `add_state/3` with `initial: true`)"

  defp format_reason({:unknown_initial, state}),
    do: "initial state #{inspect(state)} is not a declared state"

  defp format_reason({:unknown_state, {:from, state, from, event}}),
    do: "transition (#{inspect(from)} --#{inspect(event)}--> ?): unknown :from state #{inspect(state)}"

  defp format_reason({:unknown_state, {:to, state, from, event}}),
    do: "transition (#{inspect(from)} --#{inspect(event)}--> ?): unknown :to state #{inspect(state)}"

  defp format_reason({:duplicate_unguarded, {from, event}}),
    do: "multiple unguarded transitions from #{inspect(from)} on event #{inspect(event)}: the second would be unreachable"

  defp format_reason({:bad_arity, {field, _value}}),
    do: "#{field} hook/guard must be a function of arity 3"

  defp format_reason(other),
    do: inspect(other)
end

defmodule Statex.TransitionError do
  @moduledoc """
  Raised by `Statex.transition!/3` and `Statex.new!/2` on failure.

  Carries the `reason`, the `instance` at the time of failure, and the
  `event` and `payload` that triggered the transition.
  """

  defexception [:reason, :instance, :event, :payload]

  @impl true
  def message(%{reason: :no_transition, event: event, instance: instance}) do
    "No transition from state #{inspect(instance.state)} on event #{inspect(event)}"
  end

  def message(%{reason: {:guarded, _transitions}, event: event, instance: instance}) do
    "All guards rejected transition from state #{inspect(instance.state)} on event #{inspect(event)}"
  end

  def message(%{reason: {:hook_failed, hook, inner}, event: nil, instance: instance}) do
    "#{hook} hook for initial state #{inspect(instance.state)} failed: #{inspect(inner)}"
  end

  def message(%{reason: {:hook_failed, hook, inner}, event: event, instance: instance}) do
    "#{hook} hook failed during transition from #{inspect(instance.state)} on event #{inspect(event)}: #{inspect(inner)}"
  end

  def message(%{reason: reason, event: event}) do
    "Transition failed for event #{inspect(event)}: #{inspect(reason)}"
  end
end

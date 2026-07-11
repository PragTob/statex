defmodule Statex.Transition do
  @moduledoc """
  Represents a single transition in a state machine definition.

  A transition connects a `from` state to a `to` state via an `event`.

  - `guard` is an optional arity-3 predicate. When present, the transition
    only fires if `guard.(instance, event, payload)` returns `true`.
  - `action` is an optional arity-3 function that updates extended data.
    It runs between the `exit` hook of the source state and the `entry` hook
    of the target state.

  Transitions are matched in declaration order; the first one whose guard
  passes is taken (first-match-wins).
  """

  @typedoc "An arity-3 guard: `(instance, event, payload) :: boolean()`"
  @type guard :: (term(), atom(), term() -> boolean())

  @typedoc "An arity-3 action: `(instance, event, payload) :: {:ok, data} | {:error, reason}`"
  @type action :: (term(), atom(), term() -> {:ok, term()} | {:error, term()})

  @type t :: %__MODULE__{
          from: atom(),
          event: atom(),
          to: atom(),
          guard: guard() | nil,
          action: action() | nil
        }

  defstruct [:from, :event, :to, guard: nil, action: nil]

  @doc false
  @spec from_stored(atom(), atom(), Statex.State.outgoing_transition()) :: t()
  def from_stored(from, event, {to, guard, action}) do
    %__MODULE__{from: from, event: event, to: to, guard: guard, action: action}
  end
end

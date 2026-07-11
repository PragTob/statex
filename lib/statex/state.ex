defmodule Statex.State do
  @moduledoc """
  Represents a single state in a state machine definition.

  States are declared via `Statex.add_state/3`. The `entry` and `exit` hooks
  are optional arity-3 functions called as `hook.(instance, event, payload)`,
  returning `{:ok, new_data}` or `{:error, reason}`.

  Outgoing transitions are stored in `transitions` as a map from event name to
  a list of `t:Statex.outgoing_transition/0` tuples (`{to, guard, action}`),
  in declaration order. This is the internal stored form; the public
  `Statex.Transition` struct is rebuilt at introspection boundaries.
  """

  @typedoc """
  A hook function called on state entry or exit.

  Receives the current `Statex.Instance.t()`, the event atom (or `nil` on machine initialization), and the
  caller-supplied payload. Returns the updated extended data or an error.
  """
  @type hook :: (Statex.Instance.t(), atom() | nil, term() -> {:ok, term()} | {:error, term()})

  @typedoc false
  @type outgoing_transition ::
          {to :: atom(), guard :: Statex.Transition.guard() | nil,
           action :: Statex.Transition.action() | nil}

  @type t :: %__MODULE__{
          name: atom(),
          final?: boolean(),
          entry: hook() | nil,
          exit: hook() | nil,
          transitions: %{atom() => [outgoing_transition()]}
        }

  defstruct [:name, final?: false, entry: nil, exit: nil, transitions: %{}]
end

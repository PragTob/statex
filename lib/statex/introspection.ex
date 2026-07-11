defmodule Statex.Introspection do
  @moduledoc """
  Introspection helpers for state machine definitions and instances.

  All functions accept either a `Statex.Definition` or a `Statex.Instance`.
  When an instance is given, its embedded definition is used.
  """

  alias Statex.Definition
  alias Statex.Instance
  alias Statex.Transition

  @doc """
  Returns the list of event names that have at least one transition from
  `state`. Duplicates are removed; order follows declaration order.
  """
  @spec events_from(Definition.t() | Instance.t(), atom()) :: [atom()]
  def events_from(%Instance{} = instance, state),
    do: events_from(instance.definition, state)

  def events_from(%Definition{} = defn, state) do
    state_def = Map.fetch!(defn.states, state)
    Map.keys(state_def.transitions)
  end

  @doc """
  Returns all `Statex.Transition` structs that originate from `state`.
  """
  @spec transitions_from(Definition.t() | Instance.t(), atom()) :: [Transition.t()]
  def transitions_from(%Instance{} = instance, state),
    do: transitions_from(instance.definition, state)

  def transitions_from(%Definition{} = defn, state) do
    state_def = Map.fetch!(defn.states, state)

    Enum.flat_map(state_def.transitions, fn {event, transitions} ->
      Enum.map(transitions, &Transition.from_stored(state, event, &1))
    end)
  end

  @doc """
  Returns the set of states reachable from the initial state via
  breadth-first search over the transition graph.
  """
  @spec reachable_states(Definition.t()) :: MapSet.t(atom())
  def reachable_states(%Definition{} = defn),
    do: bfs([defn.initial], defn.states, MapSet.new([defn.initial]))

  @doc """
  Returns the set of states that cannot be reached from the initial state.
  These states are effectively dead code in the definition.
  """
  @spec unreachable_states(Definition.t()) :: MapSet.t(atom())
  def unreachable_states(%Definition{} = defn) do
    all = MapSet.new(Map.keys(defn.states))
    MapSet.difference(all, reachable_states(defn))
  end

  @doc """
  Renders the definition as a [Mermaid](https://mermaid.js.org/) `stateDiagram-v2`
  diagram string.

  ## Options

  - `:title` — optional diagram title string. Defaults to `nil` (no title).

  ## Example

      Statex.to_mermaid(definition)
      #=> \"\"\"
      #=> stateDiagram-v2
      #=>   [*] --> idle
      #=>   idle --> has_credit: insert_coin
      #=>   has_credit --> has_credit: select
      #=>   has_credit --> idle: refund
      #=> \"\"\"
  """
  @spec to_mermaid(Definition.t(), keyword()) :: String.t()
  def to_mermaid(%Definition{} = defn, opts \\ []) do
    title = Keyword.get(opts, :title)

    header = ["stateDiagram-v2"]

    title_line =
      if title, do: ["  title: #{title}"], else: []

    initial_line = ["  [*] --> #{defn.initial}"]

    transition_lines =
      Enum.map(Definition.all_transitions(defn), fn t ->
        label = if t.guard, do: "#{t.event} [guard]", else: "#{t.event}"
        "  #{t.from} --> #{t.to}: #{label}"
      end)

    final_lines =
      defn.states
      |> Enum.filter(fn {_name, state} -> state.final? end)
      |> Enum.map(fn {name, _state} -> "  #{name} --> [*]" end)

    (header ++ title_line ++ initial_line ++ transition_lines ++ final_lines)
    |> Enum.join("\n")
  end

  # --- Private helpers ---

  defp bfs([], _states, visited), do: visited

  defp bfs([state | rest], states, visited) do
    state_def = Map.fetch!(states, state)

    neighbors =
      state_def.transitions
      |> Enum.flat_map(fn {_event, transitions} ->
        Enum.map(transitions, fn {to, _guard, _action} -> to end)
      end)
      |> Enum.reject(&MapSet.member?(visited, &1))

    new_visited = Enum.reduce(neighbors, visited, &MapSet.put(&2, &1))
    bfs(rest ++ neighbors, states, new_visited)
  end
end

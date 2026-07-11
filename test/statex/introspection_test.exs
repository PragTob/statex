defmodule Statex.IntrospectionTest do
  use ExUnit.Case, async: true

  alias Statex.Introspection
  alias Statex.Transition

  @machine Statex.define()
           |> Statex.add_state(:idle, initial: true)
           |> Statex.add_state(:running)
           |> Statex.add_state(:paused)
           |> Statex.add_state(:done, final: true)
           |> Statex.add_state(:orphan)
           |> Statex.add_transition(:idle, :start, :running)
           |> Statex.add_transition(:running, :pause, :paused)
           |> Statex.add_transition(:running, :finish, :done)
           |> Statex.add_transition(:paused, :resume, :running)
           |> Statex.compile!()

  describe "events_from/2" do
    test "returns event atoms available from a given state" do
      events = Introspection.events_from(@machine, :running)
      assert Enum.sort(events) == [:finish, :pause]
    end

    test "returns empty list for a state with no outgoing transitions" do
      assert Introspection.events_from(@machine, :done) == []
    end

    test "returns empty list for an orphan state" do
      assert Introspection.events_from(@machine, :orphan) == []
    end

    test "deduplicates events when multiple transitions share the same event name" do
      guard = fn _i, _e, _p -> true end

      definition =
        Statex.define()
        |> Statex.add_state(:a, initial: true)
        |> Statex.add_state(:b)
        |> Statex.add_state(:c)
        |> Statex.add_transition(:a, :go, :b, guard: guard)
        |> Statex.add_transition(:a, :go, :c)
        |> Statex.compile!()

      events = Introspection.events_from(definition, :a)
      assert events == [:go]
    end

    test "accepts an instance in place of a definition" do
      {:ok, m} = Statex.new(@machine, nil)
      assert Introspection.events_from(m, :idle) == [:start]
    end
  end

  describe "transitions_from/2" do
    test "returns transition structs for a given state" do
      transitions = Introspection.transitions_from(@machine, :idle)
      assert length(transitions) == 1
      [%Transition{from: :idle, event: :start, to: :running}] = transitions
    end

    test "returns multiple transitions when a state has several" do
      transitions = Introspection.transitions_from(@machine, :running)
      assert length(transitions) == 2
    end

    test "returns empty list for a terminal state without transitions" do
      assert Introspection.transitions_from(@machine, :done) == []
    end

    test "accepts an instance" do
      {:ok, machine} = Statex.new(@machine, nil)
      transitions = Introspection.transitions_from(machine, :idle)
      assert length(transitions) == 1
    end
  end

  describe "reachable_states/1" do
    test "includes all states reachable from the initial state via BFS" do
      reachable = Introspection.reachable_states(@machine)
      assert MapSet.equal?(reachable, MapSet.new([:idle, :running, :paused, :done]))
    end

    test "includes the initial state even with no outgoing transitions" do
      definition =
        Statex.define()
        |> Statex.add_state(:only, initial: true)
        |> Statex.compile!()

      reachable = Introspection.reachable_states(definition)
      assert MapSet.equal?(reachable, MapSet.new([:only]))
    end
  end

  describe "unreachable_states/1" do
    test "returns states not reachable from the initial state" do
      unreachable = Introspection.unreachable_states(@machine)
      assert MapSet.equal?(unreachable, MapSet.new([:orphan]))
    end

    test "returns empty set when every state is reachable" do
      definition =
        Statex.define()
        |> Statex.add_state(:a, initial: true)
        |> Statex.add_state(:b)
        |> Statex.add_transition(:a, :go, :b)
        |> Statex.compile!()

      assert definition
             |> Introspection.unreachable_states()
             |> Enum.empty?()
    end
  end

  describe "to_mermaid/2" do
    test "renders the machine as a Mermaid diagram" do
      mermaid = Introspection.to_mermaid(@machine)

      assert mermaid ==
               """
               stateDiagram-v2
                 [*] --> idle
                 running --> paused: pause
                 running --> done: finish
                 idle --> running: start
                 paused --> running: resume
                 done --> [*]
               """
               |> String.trim_trailing()

      assert String.starts_with?(mermaid, "stateDiagram-v2")
    end

    test "includes title line when :title option is given" do
      mermaid = Introspection.to_mermaid(@machine, title: "My Machine")
      assert mermaid =~ "title: My Machine"
    end
  end
end

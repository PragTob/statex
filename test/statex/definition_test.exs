defmodule Statex.DefinitionTest do
  use ExUnit.Case, async: true

  alias Statex.Definition
  alias Statex.Introspection
  alias Statex.State
  alias Statex.Transition

  describe "new/0" do
    test "returns an empty Definition" do
      assert %Definition{states: %{}, initial: nil} = Definition.new()
    end
  end

  describe "new/1 with a declarative map" do
    test "builds states and transitions from a minimal map" do
      definition =
        Definition.new(%{
          initial: :idle,
          states: %{idle: %{}, running: %{}},
          transitions: [%{from: :idle, event: :start, to: :running}]
        })

      assert %Definition{initial: :idle} = definition
      assert Map.has_key?(definition.states, :idle)
      assert Map.has_key?(definition.states, :running)

      assert [%Transition{from: :idle, event: :start, to: :running}] =
               Introspection.transitions_from(definition, :idle)
    end

    test "sets entry and exit hooks from state opts" do
      entry = fn _inst, _event, _payload -> {:ok, nil} end
      exit_ = fn _inst, _event, _payload -> {:ok, nil} end

      definition =
        Definition.new(%{
          initial: :idle,
          states: %{idle: %{entry: entry, exit: exit_}},
          transitions: []
        })

      assert definition.states[:idle].entry == entry
      assert definition.states[:idle].exit == exit_
    end

    test "marks state as final when final: true in state opts" do
      definition =
        Definition.new(%{
          initial: :idle,
          states: %{idle: %{}, done: %{final: true}},
          transitions: []
        })

      assert definition.states[:done].final? == true
      assert definition.states[:idle].final? == false
    end

    test "sets guard and action on transitions from map" do
      guard = fn _i, _e, _p -> true end
      action = fn _i, _e, _p -> {:ok, nil} end

      definition =
        Definition.new(%{
          initial: :idle,
          states: %{idle: %{}, running: %{}},
          transitions: [%{from: :idle, event: :start, to: :running, guard: guard, action: action}]
        })

      [transition] = Introspection.transitions_from(definition, :idle)
      assert transition.guard == guard
      assert transition.action == action
    end

    test "handles empty states and transitions" do
      definition = Definition.new(%{initial: :a})
      assert definition.initial == :a
      assert definition.states == %{}
    end
  end

  describe "add_state/3" do
    test "adds a state with default values" do
      definition = Definition.add_state(Definition.new(), :idle)

      assert Map.has_key?(definition.states, :idle)

      assert %State{name: :idle, final?: false, entry: nil, exit: nil} =
               definition.states[:idle]
    end

    test "sets definition.initial when initial: true" do
      definition = Definition.add_state(Definition.new(), :idle, initial: true)
      assert definition.initial == :idle
    end

    test "does not set initial when initial: false (default)" do
      definition = Definition.add_state(Definition.new(), :idle)
      assert definition.initial == nil
    end

    test "sets final? on the State struct when final: true" do
      definition = Definition.add_state(Definition.new(), :done, final: true)
      assert definition.states[:done].final? == true
    end

    test "stores entry and exit hooks on the State" do
      entry = fn _i, _e, _p -> {:ok, nil} end
      exit_ = fn _i, _e, _p -> {:ok, nil} end

      definition =
        Definition.add_state(Definition.new(), :idle, entry: entry, exit: exit_)

      assert definition.states[:idle].entry == entry
      assert definition.states[:idle].exit == exit_
    end

    test "accumulates multiple states" do
      definition =
        Definition.new()
        |> Definition.add_state(:a)
        |> Definition.add_state(:b)
        |> Definition.add_state(:c)

      assert map_size(definition.states) == 3
      assert Map.has_key?(definition.states, :a)
      assert Map.has_key?(definition.states, :b)
      assert Map.has_key?(definition.states, :c)
    end

    test "last call wins when the same name is added twice" do
      entry = fn _i, _e, _p -> {:ok, :new} end

      definition =
        Definition.new()
        |> Definition.add_state(:idle)
        |> Definition.add_state(:idle, entry: entry)

      assert definition.states[:idle].entry == entry
    end
  end

  describe "add_transition/5" do
    test "adds a transition with no guard or action" do
      definition =
        Definition.new()
        |> Definition.add_state(:a)
        |> Definition.add_state(:b)
        |> Definition.add_transition(:a, :go, :b)

      assert [%Transition{from: :a, event: :go, to: :b, guard: nil, action: nil}] =
               Introspection.transitions_from(definition, :a)
    end

    test "stores guard and action" do
      guard = fn _i, _e, _p -> true end
      action = fn _i, _e, _p -> {:ok, nil} end

      definition =
        Definition.new()
        |> Definition.add_state(:a)
        |> Definition.add_state(:b)
        |> Definition.add_transition(:a, :go, :b, guard: guard, action: action)

      [transition] = Introspection.transitions_from(definition, :a)
      assert transition.guard == guard
      assert transition.action == action
    end

    test "preserves declaration order within a {from, event} bucket" do
      g1 = fn _i, _e, _p -> true end
      g2 = fn _i, _e, _p -> false end

      definition =
        Definition.new()
        |> Definition.add_state(:a)
        |> Definition.add_state(:b)
        |> Definition.add_state(:c)
        |> Definition.add_transition(:a, :go, :b, guard: g1)
        |> Definition.add_transition(:a, :go, :c, guard: g2)

      [first, second] = Introspection.transitions_from(definition, :a)
      assert first.to == :b
      assert second.to == :c
    end

    test "raises ArgumentError when the from state has not been declared" do
      assert_raise ArgumentError, ~r/unknown state :ghost/, fn ->
        Definition.add_transition(Definition.new(), :ghost, :go, :somewhere)
      end
    end
  end

  describe "compile/1" do
    test "returns {:ok, definition} for a valid definition" do
      assert {:ok, definition} =
               Definition.new()
               |> Definition.add_state(:idle, initial: true)
               |> Definition.add_state(:running)
               |> Definition.add_transition(:idle, :start, :running)
               |> Definition.compile()

      assert %Definition{initial: :idle} = definition
      assert Map.has_key?(definition.states, :idle)
      assert Map.has_key?(definition.states, :running)
    end

    test "returns the same struct unchanged on success" do
      definition =
        Definition.add_state(Definition.new(), :idle, initial: true)

      assert {:ok, validated} = Definition.compile(definition)
      assert validated == definition
    end

    test "error: no states declared" do
      assert {:error, reasons} = Definition.compile(Definition.new())

      assert [:no_initial, :no_states] == reasons
    end

    test "error: no initial state" do
      assert {:error, reasons} =
               Definition.new()
               |> Definition.add_state(:idle)
               |> Definition.compile()

      assert [:no_initial] == reasons
    end

    test "error: initial state not in declared states" do
      assert {:error, reasons} =
               Definition.new(%{
                 initial: :ghost,
                 states: %{idle: %{}},
                 transitions: []
               })
               |> Definition.compile()

      assert [{:unknown_initial, :ghost}] == reasons
    end

    test "adding a transition from an undeclared state raises at add_transition time" do
      assert_raise ArgumentError, ~r/unknown state :ghost/, fn ->
        Definition.new()
        |> Definition.add_state(:idle, initial: true)
        |> Definition.add_transition(:ghost, :go, :idle)
      end
    end

    test "error: transition :to references unknown state" do
      assert {:error, reasons} =
               Definition.new()
               |> Definition.add_state(:idle, initial: true)
               |> Definition.add_transition(:idle, :go, :ghost)
               |> Definition.compile()

      assert [{:unknown_state, {:to, :ghost, :idle, :go}}] == reasons
    end

    test "error: two unguarded transitions share {from, event}" do
      assert {:error, reasons} =
               Definition.new()
               |> Definition.add_state(:a, initial: true)
               |> Definition.add_state(:b)
               |> Definition.add_state(:c)
               |> Definition.add_transition(:a, :go, :b)
               |> Definition.add_transition(:a, :go, :c)
               |> Definition.compile()

      assert [{:duplicate_unguarded, {:a, :go}}] == reasons
    end

    test "no error: one guarded + one unguarded transition on same {from, event}" do
      guard = fn _i, _e, _p -> true end

      assert {:ok, _} =
               Definition.new()
               |> Definition.add_state(:a, initial: true)
               |> Definition.add_state(:b)
               |> Definition.add_state(:c)
               |> Definition.add_transition(:a, :go, :b, guard: guard)
               |> Definition.add_transition(:a, :go, :c)
               |> Definition.compile()
    end

    test "no error: two guarded transitions on same {from, event}" do
      g1 = fn _i, _e, _p -> true end
      g2 = fn _i, _e, _p -> false end

      assert {:ok, _} =
               Definition.new()
               |> Definition.add_state(:a, initial: true)
               |> Definition.add_state(:b)
               |> Definition.add_state(:c)
               |> Definition.add_transition(:a, :go, :b, guard: g1)
               |> Definition.add_transition(:a, :go, :c, guard: g2)
               |> Definition.compile()
    end

    test "error: guard is not arity-3" do
      bad = fn _x -> true end

      assert {:error, reasons} =
               Definition.new()
               |> Definition.add_state(:a, initial: true)
               |> Definition.add_state(:b)
               |> Definition.add_transition(:a, :go, :b, guard: bad)
               |> Definition.compile()

      assert [{:bad_arity, {:guard, bad}}] == reasons
    end

    test "error: action is not arity-3" do
      bad = fn -> {:ok, nil} end

      assert {:error, reasons} =
               Definition.new()
               |> Definition.add_state(:a, initial: true)
               |> Definition.add_state(:b)
               |> Definition.add_transition(:a, :go, :b, action: bad)
               |> Definition.compile()

      assert [{:bad_arity, {:action, bad}}] == reasons
    end

    test "error: entry hook is not arity-3" do
      bad = fn _x, _y -> {:ok, nil} end

      assert {:error, reasons} =
               Definition.new()
               |> Definition.add_state(:a, initial: true, entry: bad)
               |> Definition.compile()

      assert [{:bad_arity, {:entry, bad}}] == reasons
    end

    test "error: exit hook is not arity-3" do
      bad = fn -> {:ok, nil} end

      assert {:error, reasons} =
               Definition.new()
               |> Definition.add_state(:a, initial: true, exit: bad)
               |> Definition.compile()

      assert [{:bad_arity, {:exit, bad}}] == reasons
    end

    test "collects multiple independent errors at once" do
      assert {:error, reasons} =
               Definition.new()
               |> Definition.add_state(:a, initial: true)
               |> Definition.add_state(:b)
               |> Definition.add_transition(:a, :go, :b)
               |> Definition.add_transition(:a, :go, :b)
               |> Definition.add_transition(:a, :go, :ghost)
               |> Definition.compile()

      assert {:duplicate_unguarded, {:a, :go}} in reasons
      assert Enum.any?(reasons, &match?({:unknown_state, {:to, :ghost, _, _}}, &1))

      assert Enum.sort(reasons) == [
               {:duplicate_unguarded, {:a, :go}},
               {:unknown_state, {:to, :ghost, :a, :go}}
             ]
    end
  end

  describe "compile!/1" do
    test "raises Statex.CompileError on an invalid definition" do
      exception =
        assert_raise Statex.CompileError, fn ->
          Definition.compile!(Definition.new())
        end

      assert exception.reasons != []
      assert String.contains?(Exception.message(exception), "Invalid state machine definition")
    end

    test "returns the definition on success" do
      assert %Definition{initial: :idle} =
               Definition.new()
               |> Definition.add_state(:idle, initial: true)
               |> Definition.compile!()
    end
  end

  describe "validate/1" do
    test "returns [] for a valid definition" do
      definition =
        Definition.new()
        |> Definition.add_state(:a, initial: true)
        |> Definition.add_state(:b)
        |> Definition.add_transition(:a, :go, :b)

      assert Definition.validate(definition) == []
    end

    test "returns a list of reasons for an invalid definition" do
      reasons = Definition.new() |> Definition.validate()
      assert is_list(reasons)
      assert reasons != []
    end
  end
end

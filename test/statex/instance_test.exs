defmodule Statex.InstanceTest do
  use ExUnit.Case, async: true

  alias Statex.Instance

  @definition Statex.define()
              |> Statex.add_state(:idle, initial: true)
              |> Statex.add_state(:running)
              |> Statex.add_state(:done, final: true)
              |> Statex.add_transition(:idle, :start, :running)
              |> Statex.add_transition(:running, :stop, :done)
              |> Statex.compile!()

  describe "new/2" do
    test "creates an instance in the initial state with supplied data" do
      assert {:ok, machine} = Instance.new(@definition, %{count: 0})
      assert machine.state == :idle
      assert machine.data == %{count: 0}
    end

    test "runs the initial state's entry hook; data reflects its return" do
      entry = fn _inst, _event, _payload -> {:ok, :initialized} end

      definition =
        Statex.define()
        |> Statex.add_state(:idle, initial: true, entry: entry)
        |> Statex.compile!()

      assert {:ok, machine} = Instance.new(definition, :original)
      assert machine.data == :initialized
    end

    test "returns {:error, reason} when the entry hook fails" do
      entry = fn _inst, _event, _payload -> {:error, :boom} end

      definition =
        Statex.define()
        |> Statex.add_state(:idle, initial: true, entry: entry)
        |> Statex.compile!()

      assert {:error, {:hook_failed, :entry, :boom}} = Instance.new(definition, nil)
    end

    test "entry hook receives event=nil and payload=nil on init" do
      entry = fn _inst, event, payload -> {:ok, {event, payload}} end

      definition =
        Statex.define()
        |> Statex.add_state(:idle, initial: true, entry: entry)
        |> Statex.compile!()

      assert {:ok, machine} = Instance.new(definition, nil)
      assert machine.data == {nil, nil}
    end

    test "accepts an uncompiled definition (compile! is optional)" do
      definition = Statex.define() |> Statex.add_state(:idle, initial: true)
      assert {:ok, machine} = Instance.new(definition, nil)
      assert machine.state == :idle
    end
  end

  describe "new!/2" do
    test "returns the instance on success" do
      machine = Instance.new!(@definition, nil)
      assert machine.state == :idle
    end

    test "raises TransitionError when the entry hook fails" do
      entry = fn _inst, _event, _payload -> {:error, :boom} end

      definition =
        Statex.define()
        |> Statex.add_state(:idle, initial: true, entry: entry)
        |> Statex.compile!()

      assert_raise Statex.TransitionError, fn ->
        Instance.new!(definition, nil)
      end
    end
  end

  describe "accessors" do
    test "final?/1 returns false when not in a final state" do
      {:ok, machine} = Instance.new(@definition, nil)
      refute Instance.final?(machine)
    end

    test "final?/1 returns true when in a final state" do
      assert Instance.new!(@definition, nil)
             |> Instance.transition!(:start)
             |> Instance.transition!(:stop)
             |> Instance.final?()
    end
  end

  describe "transition/3 — basic routing" do
    test "transitions to the target state" do
      {:ok, machine} = Instance.new(@definition, nil)
      assert {:ok, machine} = Instance.transition(machine, :start)
      assert machine.state == :running
    end

    test "returns {:error, :no_transition} for an event valid in another state" do
      {:ok, machine} = Instance.new(@definition, nil)
      # :stop is only valid from :running, not :idle
      assert {:error, :no_transition} = Instance.transition(machine, :stop)
    end

    test "payload defaults to nil" do
      action = fn instance, _event, payload -> {:ok, {instance.data, payload}} end

      definition =
        Statex.define()
        |> Statex.add_state(:a, initial: true)
        |> Statex.add_state(:b)
        |> Statex.add_transition(:a, :go, :b, action: action)
        |> Statex.compile!()

      {:ok, machine} = Instance.new(definition, :base)
      {:ok, machine} = Instance.transition(machine, :go)
      assert machine.data == {:base, nil}
    end

    test "passes payload to guard, action, and entry hooks" do
      action = fn instance, _event, payload -> {:ok, {instance.data, payload}} end

      definition =
        Statex.define()
        |> Statex.add_state(:a, initial: true)
        |> Statex.add_state(:b)
        |> Statex.add_transition(:a, :go, :b, action: action)
        |> Statex.compile!()

      {:ok, machine} = Instance.new(definition, :base)
      {:ok, machine} = Instance.transition(machine, :go, :my_payload)
      assert machine.data == {:base, :my_payload}
    end
  end

  describe "transition/3 — guard resolution" do
    test "returns {:error, {:guarded, candidates}} when all guards reject" do
      guard = fn _inst, _event, _payload -> false end

      definition =
        Statex.define()
        |> Statex.add_state(:a, initial: true)
        |> Statex.add_state(:b)
        |> Statex.add_transition(:a, :go, :b, guard: guard)
        |> Statex.compile!()

      {:ok, machine} = Instance.new(definition, nil)
      assert {:error, {:guarded, [_]}} = Instance.transition(machine, :go)
    end

    test "first-match-wins: takes first transition whose guard passes" do
      always = fn _i, _e, _p -> true end
      never = fn _i, _e, _p -> false end

      definition =
        Statex.define()
        |> Statex.add_state(:a, initial: true)
        |> Statex.add_state(:b)
        |> Statex.add_state(:c)
        |> Statex.add_transition(:a, :go, :b, guard: always)
        |> Statex.add_transition(:a, :go, :c, guard: never)
        |> Statex.compile!()

      {:ok, machine} = Instance.new(definition, nil)
      assert {:ok, machine} = Instance.transition(machine, :go)
      assert machine.state == :b
    end

    test "skips guarded transitions until one passes" do
      skip = fn _i, _e, _p -> false end
      pass = fn _i, _e, _p -> true end

      definition =
        Statex.define()
        |> Statex.add_state(:a, initial: true)
        |> Statex.add_state(:b)
        |> Statex.add_state(:c)
        |> Statex.add_transition(:a, :go, :b, guard: skip)
        |> Statex.add_transition(:a, :go, :c, guard: pass)
        |> Statex.compile!()

      {:ok, machine} = Instance.new(definition, nil)
      assert {:ok, machine} = Instance.transition(machine, :go)
      assert machine.state == :c
    end

    test "guard receives the live instance, event, and payload" do
      guard =
        fn instance, event, payload ->
          send(self(), {instance.state, event, payload})
        end

      definition =
        Statex.define()
        |> Statex.add_state(:a, initial: true)
        |> Statex.add_state(:b)
        |> Statex.add_transition(:a, :go, :b, guard: guard)
        |> Statex.compile!()

      {:ok, machine} = Instance.new(definition, nil)
      assert {:ok, machine} = Instance.transition(machine, :go, :check)
      assert_received {:a, :go, :check}
      assert machine.state == :b
    end
  end

  describe "transition/3 — hook execution order" do
    test "runs exit → action → entry, threading updated data" do
      exit_fn = fn instance, _e, _p -> {:ok, instance.data ++ [{:exit, instance.state}]} end
      action_fn = fn instance, _e, _p -> {:ok, instance.data ++ [{:action, instance.state}]} end
      entry_fn = fn instance, _e, _p -> {:ok, instance.data ++ [{:entry, instance.state}]} end

      definition =
        Statex.define()
        |> Statex.add_state(:a, initial: true, exit: exit_fn)
        |> Statex.add_state(:b, entry: entry_fn)
        |> Statex.add_transition(:a, :go, :b, action: action_fn)
        |> Statex.compile!()

      {:ok, machine} = Instance.new(definition, [])
      {:ok, machine} = Instance.transition(machine, :go)
      # historical execution order: exit → action → entry
      assert machine.data == [{:exit, :a}, {:action, :a}, {:entry, :b}]
    end

    test "short-circuits on exit hook failure; original instance returned" do
      exit_fn = fn _inst, _e, _p -> {:error, :exit_boom} end

      definition =
        Statex.define()
        |> Statex.add_state(:a, initial: true, exit: exit_fn)
        |> Statex.add_state(:b)
        |> Statex.add_transition(:a, :go, :b)
        |> Statex.compile!()

      {:ok, machine} = Instance.new(definition, :original)
      assert {:error, {:hook_failed, :exit, :exit_boom}} = Instance.transition(machine, :go)
    end

    test "short-circuits on action failure" do
      action_fn = fn _inst, _e, _p -> {:error, :action_boom} end

      definition =
        Statex.define()
        |> Statex.add_state(:a, initial: true)
        |> Statex.add_state(:b)
        |> Statex.add_transition(:a, :go, :b, action: action_fn)
        |> Statex.compile!()

      {:ok, machine} = Instance.new(definition, nil)
      assert {:error, {:hook_failed, :action, :action_boom}} = Instance.transition(machine, :go)
    end

    test "short-circuits on entry hook failure" do
      entry_fn = fn _inst, _e, _p -> {:error, :entry_boom} end

      definition =
        Statex.define()
        |> Statex.add_state(:a, initial: true)
        |> Statex.add_state(:b, entry: entry_fn)
        |> Statex.add_transition(:a, :go, :b)
        |> Statex.compile!()

      {:ok, machine} = Instance.new(definition, nil)
      assert {:error, {:hook_failed, :entry, :entry_boom}} = Instance.transition(machine, :go)
    end
  end

  describe "transition/3 — self-transitions" do
    test "external self-transition fires both exit and entry hooks" do
      exit_fn = fn instance, _e, _p -> {:ok, instance.data ++ [:exit]} end
      entry_fn = fn instance, _e, _p -> {:ok, instance.data ++ [:entry]} end

      definition =
        Statex.define()
        |> Statex.add_state(:a, initial: true, exit: exit_fn, entry: entry_fn)
        |> Statex.add_transition(:a, :loop, :a)
        |> Statex.compile!()

      # new/2 runs initial entry → data becomes [:entry]
      {:ok, machine} = Instance.new(definition, [])
      {:ok, machine} = Instance.transition(machine, :loop)
      # loop: exit → [:entry, :exit], then entry → [:entry, :exit, :entry]
      assert machine.data == [:entry, :exit, :entry]
      assert machine.state == :a
    end
  end

  describe "transition!/3" do
    test "returns the new instance on success" do
      {:ok, machine} = Instance.new(@definition, nil)
      machine = Instance.transition!(machine, :start)
      assert machine.state == :running
    end

    test "raises TransitionError with :no_transition reason" do
      {:ok, machine} = Instance.new(@definition, nil)

      error =
        assert_raise Statex.TransitionError, fn ->
          Instance.transition!(machine, :stop)
        end

      assert error.reason == :no_transition
      assert error.event == :stop
      assert error.instance == machine
    end

    test "raises TransitionError with {:guarded, _} reason" do
      guard = fn _i, _e, _p -> false end

      definition =
        Statex.define()
        |> Statex.add_state(:a, initial: true)
        |> Statex.add_state(:b)
        |> Statex.add_transition(:a, :go, :b, guard: guard)
        |> Statex.compile!()

      {:ok, machine} = Instance.new(definition, nil)

      error =
        assert_raise Statex.TransitionError, fn ->
          Instance.transition!(machine, :go)
        end

      assert match?({:guarded, [_]}, error.reason)
    end

    test "transition!/3 with payload raises on failure" do
      {:ok, machine} = Instance.new(@definition, nil)

      error =
        assert_raise Statex.TransitionError, fn ->
          Instance.transition!(machine, :stop, :some_payload)
        end

      assert error.payload == :some_payload
    end
  end
end

defmodule Statex.Examples.VendingMachineTest do
  @moduledoc """
  A living example of `Statex` in action.

  The vending machine has two states:

  - `:idle` — waiting for coins
  - `:has_credit` — at least one coin inserted

  Events:

  - `:insert_coin` — accepted in any state; accumulates credit
  - `:select` — only fires when `credit >= price`; dispenses the item
  - `:refund` — returns credit and goes back to `:idle`

  This module demonstrates the canonical compile-time pattern:
  define callbacks with `def`, reference them via `&__MODULE__.fun/3`,
  and freeze the definition in a `@machine` module attribute so that
  any mistake in the definition is caught at `mix compile`.
  """

  use ExUnit.Case, async: true

  @prices %{soda: 100, water: 75}

  # Callbacks are `def` so `&__MODULE__.fun/3` captures resolve correctly
  # as external calls when the module attribute is evaluated at compile time.

  def add_credit(instance, :insert_coin, %{value: v}),
    do: {:ok, Map.update!(instance.data, :credit, &(&1 + v))}

  def exact_price?(instance, :select, %{item: item}),
    do: instance.data.credit == Map.fetch!(@prices, item)

  def over_price?(instance, :select, %{item: item}),
    do: instance.data.credit > Map.fetch!(@prices, item)

  def dispense(instance, :select, %{item: item}) do
    price = Map.fetch!(@prices, item)

    {:ok,
     instance.data
     |> Map.update!(:credit, &(&1 - price))
     |> Map.update(:dispensed, [item], &[item | &1])}
  end

  def refund(instance, :refund, _payload),
    do: {:ok, %{instance.data | credit: 0}}

  @machine Statex.define()
           |> Statex.add_state(:idle, initial: true)
           |> Statex.add_state(:has_credit)
           |> Statex.add_transition(:idle, :insert_coin, :has_credit,
             action: &__MODULE__.add_credit/3
           )
           |> Statex.add_transition(:has_credit, :insert_coin, :has_credit,
             action: &__MODULE__.add_credit/3
           )
           |> Statex.add_transition(:has_credit, :select, :has_credit,
             guard: &__MODULE__.over_price?/3,
             action: &__MODULE__.dispense/3
           )
           |> Statex.add_transition(:has_credit, :select, :idle,
             guard: &__MODULE__.exact_price?/3,
             action: &__MODULE__.dispense/3
           )
           |> Statex.add_transition(:has_credit, :refund, :idle, action: &__MODULE__.refund/3)
           |> Statex.compile!()

  def definition, do: @machine

  defp new_machine, do: Statex.new!(@machine, %{credit: 0, dispensed: []})

  describe "initial state" do
    test "machine starts in :idle" do
      assert new_machine().state == :idle
    end

    test "credit starts at 0" do
      assert new_machine().data.credit == 0
    end
  end

  describe "insert_coin" do
    test "transitions from :idle to :has_credit" do
      {:ok, machine} = Statex.transition(new_machine(), :insert_coin, %{value: 25})
      assert machine.state == :has_credit
      assert machine.data.credit == 25
    end

    test "accumulates credit across multiple coins" do
      {:ok, machine} = Statex.transition(new_machine(), :insert_coin, %{value: 50})
      {:ok, machine} = Statex.transition(machine, :insert_coin, %{value: 50})
      assert machine.data.credit == 100
      assert machine.state == :has_credit
    end
  end

  describe "select" do
    test "dispenses item when credit is sufficient" do
      {:ok, machine} = Statex.transition(new_machine(), :insert_coin, %{value: 100})
      {:ok, machine} = Statex.transition(machine, :select, %{item: :soda})
      assert :soda in machine.data.dispensed
      assert machine.data.credit == 0
      assert machine.state == :idle
    end

    test "stays in :has_credit after selection, if there is credit" do
      {:ok, machine} = Statex.transition(new_machine(), :insert_coin, %{value: 100})
      {:ok, machine} = Statex.transition(machine, :select, %{item: :water})
      assert machine.state == :has_credit
      assert machine.data.credit == 25
    end

    test "guard rejects selection when credit is insufficient" do
      {:ok, machine} = Statex.transition(new_machine(), :insert_coin, %{value: 50})
      assert {:error, {:guarded, _}} = Statex.transition(machine, :select, %{item: :soda})
    end

    test "cannot select from :idle (no transition defined)" do
      assert {:error, :no_transition} =
               Statex.transition(new_machine(), :select, %{item: :soda})
    end

    test "can purchase multiple items sequentially" do
      {:ok, machine} = Statex.transition(new_machine(), :insert_coin, %{value: 200})
      {:ok, machine} = Statex.transition(machine, :select, %{item: :soda})
      {:ok, machine} = Statex.transition(machine, :select, %{item: :water})
      assert :soda in machine.data.dispensed
      assert :water in machine.data.dispensed
      assert machine.data.credit == 25
      assert machine.state == :has_credit
    end
  end

  describe "refund" do
    test "returns to :idle" do
      {:ok, machine} = Statex.transition(new_machine(), :insert_coin, %{value: 100})
      {:ok, machine} = Statex.transition(machine, :refund, nil)
      assert machine.state == :idle
      assert machine.data.credit == 0
    end

    test "refund from :idle is not possible" do
      assert {:error, :no_transition} = Statex.transition(new_machine(), :refund, nil)
    end
  end

  describe "introspection" do
    test "events_from/2 returns correct events for :idle" do
      assert Statex.events_from(@machine, :idle) == [:insert_coin]
    end

    test "events_from/2 returns correct events for :has_credit" do
      events = Statex.events_from(@machine, :has_credit)
      assert Enum.sort(events) == [:insert_coin, :refund, :select]
    end

    test "reachable_states/1 returns both states" do
      reachable = Statex.reachable_states(@machine)

      assert MapSet.equal?(reachable, MapSet.new([:idle, :has_credit]))
    end

    test "to_mermaid/1 produces a valid diagram" do
      mermaid = Statex.to_mermaid(@machine)

      assert mermaid ==
               """
               stateDiagram-v2
                 [*] --> idle
                 idle --> has_credit: insert_coin
                 has_credit --> has_credit: select [guard]
                 has_credit --> idle: select [guard]
                 has_credit --> has_credit: insert_coin
                 has_credit --> idle: refund
               """
               |> String.trim_trailing()
    end
  end
end

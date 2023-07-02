defmodule Pixelgame.AutomataTest do
  use Pixelgame.DataCase

  alias Pixelgame.Automata

  describe "rules" do
    alias Pixelgame.Automata.Rule

    import Pixelgame.AutomataFixtures

    @invalid_attrs %{name: nil, number: nil, rating: nil}

    test "list_rules/0 returns all rules" do
      rule = rule_fixture()
      assert Automata.list_rules() == [rule]
    end

    test "get_rule!/1 returns the rule with given id" do
      rule = rule_fixture()
      assert Automata.get_rule!(rule.id) == rule
    end

    test "create_rule/1 with valid data creates a rule" do
      valid_attrs = %{name: "some name", number: "120.5", rating: 42}

      assert {:ok, %Rule{} = rule} = Automata.create_rule(valid_attrs)
      assert rule.name == "some name"
      assert rule.number == Decimal.new("120.5")
      assert rule.rating == 42
    end

    test "create_rule/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Automata.create_rule(@invalid_attrs)
    end

    test "update_rule/2 with valid data updates the rule" do
      rule = rule_fixture()
      update_attrs = %{name: "some updated name", number: "456.7", rating: 43}

      assert {:ok, %Rule{} = rule} = Automata.update_rule(rule, update_attrs)
      assert rule.name == "some updated name"
      assert rule.number == Decimal.new("456.7")
      assert rule.rating == 43
    end

    test "update_rule/2 with invalid data returns error changeset" do
      rule = rule_fixture()
      assert {:error, %Ecto.Changeset{}} = Automata.update_rule(rule, @invalid_attrs)
      assert rule == Automata.get_rule!(rule.id)
    end

    test "delete_rule/1 deletes the rule" do
      rule = rule_fixture()
      assert {:ok, %Rule{}} = Automata.delete_rule(rule)
      assert_raise Ecto.NoResultsError, fn -> Automata.get_rule!(rule.id) end
    end

    test "change_rule/1 returns a rule changeset" do
      rule = rule_fixture()
      assert %Ecto.Changeset{} = Automata.change_rule(rule)
    end
  end
end

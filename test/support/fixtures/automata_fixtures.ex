defmodule Pixelgame.AutomataFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Pixelgame.Automata` context.
  """

  @doc """
  Generate a rule.
  """
  def rule_fixture(attrs \\ %{}) do
    {:ok, rule} =
      attrs
      |> Enum.into(%{
        name: "some name",
        number: "120.5",
        rating: 42
      })
      |> Pixelgame.Automata.create_rule()

    rule
  end
end

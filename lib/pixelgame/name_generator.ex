defmodule Pixelgame.NameGenerator do
  @adjectives {
    "alleged",
    "colluding",
    "conniving",
    "cheeky",
    "crooked",
    "default",
    "dodgy",
    "european",
    "faithless",
    "fishy",
    "flirty",
    "general",
    "grumpy",
    "gym",
    "horse",
    "illegal",
    "illegitimate",
    "illicit",
    "immoral",
    "lil",
    "level one",
    "level 100",
    "lying",
    "raging",
    "recreational",
    "shady",
    "sigma",
    "silly",
    "sleepy",
    "sus",
    "stealthy",
    "well-adjusted"
  }
  @nouns {
    "american",
    "bozo",
    "buttress",
    "bro",
    "bystander",
    "conspirator",
    "crook",
    "doorknob",
    "dreamer",
    "european",
    "friend",
    "frigate",
    "gamer",
    "homeowner",
    "joe",
    "goofball",
    "jabberwocky",
    "jockey",
    "monarch",
    "oligarch",
    "pirate",
    "practitioner",
    "sapling",
    "schmoe",
    "scoundrel",
    "scum",
    "seaman",
    "sinner",
    "snack",
    "weeb",
    "whippersnapper",
    "youngin"
  }

  @adjectives_size tuple_size(@adjectives)
  @nouns_size tuple_size(@nouns)

  @doc """
  This generates an adjective noun string with 1024 total possibilities
  """
  def generate_name() do
    adj = elem(@adjectives, :rand.uniform(@adjectives_size) - 1)
    noun = elem(@nouns, :rand.uniform(@nouns_size) - 1)
    adj <> " " <> noun
  end
end

# frozen_string_literal: true

# What the battle board draws for a party member or an antagonist
# (BattlesHelper#unit_art): an image, the variant recipe to draw it with,
# their colour for the plate, and their level.
BattleArt = Data.define(:image, :variant, :colour, :level)

# frozen_string_literal: true

# The setting's words in the pages (Vocabulary): money, HP and MP, stats,
# services and statuses, as the world names them.
module VocabularyHelper
  # The world the page is about, when there is one.
  def vocabulary_world
    @world || @campaign&.world || @battle&.campaign&.world || @location&.campaign&.world || @character&.campaign&.world
  end

  def word(key, world = vocabulary_world)
    world ? world.word(key) : Vocabulary.word({}, key)
  end

  # "150 gil", in the world's money.
  def money(amount, world = vocabulary_world)
    "#{number_with_delimiter(amount)} #{word('currency', world)}"
  end

  # What the battle player shows as it animates (battle_player_controller.js).
  def battle_words(world)
    { hp: word("hp", world), mp: word("mp", world), statuses: Battle::STATUSES.to_h { |s| [ s, word("status.#{s}", world) ] } }
  end
end

# frozen_string_literal: true

# What the GM sets up for a battle at the table (battles/_setup, under the
# stage once Battle is called: Campaign::Controls): the encounter, who
# fights, and the few things behind "More". The defaults stand in for an
# untouched form; BattlesController#create reads the same shape back.
module BattleSetup
  ENCOUNTER_SLOTS = 3

  def self.defaults(campaign)
    monster = campaign.world.monsters.order(:level).first&.slug
    {
      name: "Battle", seed: nil, escapable: "1", input_seconds: BattleRecord::DEFAULT_TIMER.to_s, terrain: "",
      # The standing first; the fallen come too, down, to be raised (and their players watch).
      characters: campaign.characters.order(:created_at).sort_by { |c| c.conscious? ? 0 : 1 }.first(4).map(&:id), antagonists: [],
      encounter: [ { monster: monster.to_s, count: "3" } ] + Array.new(ENCOUNTER_SLOTS - 1) { { monster: "", count: "1" } }
    }
  end
end

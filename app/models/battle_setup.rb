# frozen_string_literal: true

# What the GM sets up for a battle at the table (battles/_setup, under the
# stage once Battle is called: Campaign::Controls): the encounter, who
# fights, and the few things behind "More". The form is read here once, for
# the battle it starts (#start!) and for the forecast as it changes
# (Campaigns::ForecastsController), so the two never disagree. The defaults
# stand in for an untouched form.
class BattleSetup
  ENCOUNTER_SLOTS = 3
  # The most of one kind a row of the form brings (its count field says the same).
  MOST = 8

  def self.defaults(campaign)
    {
      name: "Battle", seed: nil, escapable: "1", input_seconds: BattleRecord::DEFAULT_TIMER.to_s, terrain: "",
      # The standing first; the fallen come too, down, to be raised (and their players watch).
      characters: campaign.characters.order(:created_at).sort_by { |c| c.conscious? ? 0 : 1 }.first(4).map(&:id), antagonists: [],
      # Nothing chosen for the GM: what they face is picked, one of a kind to start (a boss is one).
      encounter: Array.new(ENCOUNTER_SLOTS) { { monster: "", count: "1" } }
    }
  end

  # A form's monster rows as an encounter, { "goblin" => 5 }: blank rows
  # left out, a kind in two rows brought with both counts, and only the
  # world's own monsters. Rows arrive as { "0" => { monster:, count: } }.
  def self.encounter(world, rows, most: MOST)
    counts = JsonCasting.rows(rows).each_with_object(Hash.new(0)) do |row, kinds|
      kinds[row["monster"]] += row["count"].to_i.clamp(1, most) if row["monster"].present?
    end
    counts.slice(*world.monsters.where(slug: counts.keys).pluck(:slug))
  end

  attr_reader :campaign

  # form: the battle form's fields (BattlesController#create).
  def initialize(campaign, form)
    @campaign = campaign
    @form = form.to_h.with_indifferent_access
  end

  # Who fights: the campaign's own characters that were ticked, in the party's order.
  def characters
    @characters ||= campaign.characters.where(id: ids(:characters)).to_a
  end

  # The campaign's antagonists still at large that were ticked.
  def antagonists
    @antagonists ||= campaign.npcs.at_large.where(id: ids(:antagonists)).to_a
  end

  def encounter
    @encounter ||= self.class.encounter(campaign.world, JsonCasting.rows(@form[:encounter]).first(ENCOUNTER_SLOTS))
  end

  # The battle, started. Raises Refusal for a fight nobody can have.
  def start!
    raise Refusal, "Pick at least one character who is still standing." if characters.none?(&:conscious?)
    raise Refusal, "Pick at least one monster or antagonist." if encounter.empty? && antagonists.empty?

    BattleRecord.start!(campaign: campaign, characters: characters, name: @form[:name].presence || "Battle", encounter: encounter,
                        antagonists: antagonists, seed: @form[:seed], escapable: @form[:escapable] != "0",
                        input_seconds: @form[:input_seconds].presence&.to_i, terrain: @form[:terrain].presence_in(campaign.world.type_chart.slugs))
  end

  private

  def ids(field) = Array(@form[field]).compact_blank.map(&:to_i)
end

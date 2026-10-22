# frozen_string_literal: true

# What a GM has set up for a campaign, in the order prep goes: where the party starts, who is in the world, what will
# be played, what presses on the party, what is hidden, what they carry. Each step is done when the campaign has any of
# it; nothing here says how much is enough.
class Campaign::Preparation
  Step = Data.define(:key, :title, :why, :done, :optional)

  def initialize(campaign)
    @campaign = campaign
  end

  def steps
    @steps ||= [
      step(:start, "Put the party somewhere", "Places tell the table where it is, and roads lead to fights.", campaign.current_node_id.present?),
      step(:cast, "Add someone to talk to", "A name, a portrait and a line or two: the GM can speak as them at the table.", campaign.npcs.exists?),
      step(:scenes, "Write a scene", "A few lines for your NPCs, ending in a choice or a fight, played with one button.", campaign.scenes.exists?),
      step(:clocks, "Start a clock", "What happens if the party does nothing, ticking on rests, journeys and failed checks.", campaign.clocks.exists?),
      step(:secrets, "Write a secret", "Something the party can find out, and the things that bring it out.", campaign.secrets.exists?),
      step(:bag, "Stock the chest", "What the party starts with, in the chest or in a bag.", campaign.inventories.where("quantity > 0").exists?, optional: true)
    ]
  end

  def next_up(limit = 3) = steps.reject(&:done).first(limit)

  def done_count = steps.count(&:done)

  private

  attr_reader :campaign

  def step(key, title, why, done, optional: false) = Step.new(key, title, why, done, optional)
end

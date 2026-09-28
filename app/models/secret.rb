# frozen_string_literal: true

# Something true the party could find out ("The mayor pays the goblins").
# The GM writes them in prep, loose: not locked to a scene, so they come out
# however the table gets there. Optionally about a place or someone, so a
# field ability that uncovers things there finds the right one.
#
# Revealed, a secret is announced at the table, joins what the party knows,
# and is in the next recap.
class Secret < ApplicationRecord
  belongs_to :campaign
  belongs_to :world_front, optional: true
  belongs_to :location, optional: true
  belongs_to :npc, optional: true

  normalizes :body, with: ->(body) { body.to_s.strip }

  validates :body, presence: true, length: { maximum: 500 }
  validate :about_this_campaign

  scope :kept, -> { where(revealed_at: nil) }
  scope :revealed, -> { where.not(revealed_at: nil) }

  after_commit :broadcast

  def revealed?
    !revealed_at.nil?
  end

  # Where or who it's about, for the lists.
  def about
    [ npc&.name, location&.name ].compact.join(", ").presence
  end

  # Out at the table. by: how it came out ("Vivi's Scry"), if not the GM's telling.
  def reveal!(by: nil)
    raise Refusal, "The party already knows that" if revealed?

    transaction do
      said = campaign.narrate("#{by ? "#{by}: the" : 'The'} party learns: #{body.sub(/\.\z/, '')}.")
      # Revealed when it was said, so the recap finds it in that session.
      update!(revealed_at: said.created_at, revealed_by: by)
    end
    self
  end

  # Put back, as if never learned (a GM's slip). Nothing is said at the table.
  def conceal!
    update!(revealed_at: nil, revealed_by: nil)
  end

  # The next secret to come out where the party is: one about the place
  # they stand in, else the oldest that isn't about anywhere, else the oldest.
  def self.next_for(campaign)
    kept = campaign.secrets.kept.order(:created_at, :id)
    here = campaign.current_node&.location
    (here && kept.find_by(location: here)) || kept.find_by(location_id: nil) || kept.first
  end

  private

  def about_this_campaign
    errors.add(:location, "isn't in this campaign") if location && location.campaign_id != campaign_id
    errors.add(:npc, "isn't in this campaign") if npc && npc.campaign_id != campaign_id
  end

  def broadcast
    { false => :map, true => :map_gm }.each do |gm, stream|
      broadcast_replace_to campaign, stream, target: "party_knows", partial: "tables/party_knows", locals: { campaign: campaign, gm: gm }
    end
    broadcast_replace_to campaign, :map_gm, target: "gm_secrets", partial: "secrets/gm", locals: { campaign: campaign }
  end
end

# frozen_string_literal: true

# Something true the party could find out ("The mayor pays the goblins").
# The GM writes them in prep, loose: not locked to a scene, so they come out
# however the table gets there. Optionally about a place or someone, so a
# field ability that uncovers things there finds the right one.
#
# Revealed, a secret is announced at the table, joins what the party knows,
# and is in the next recap.
#
# A secret can come out a step at a time (docs/STORY.md, item 11): its
# steps (Clue), from a question to the truth, are found one after another
# wherever the party finds them, by an uncover, at its place, from its
# person, or when the GM says, and after the last, the secret itself. Its
# key lets story rows ask how far the party has got (Campaign::Moment).
class Secret < ApplicationRecord
  include CampaignPages

  belongs_to :campaign
  belongs_to :world_front, optional: true
  belongs_to :location, optional: true
  belongs_to :npc, optional: true
  # Going around as a rumour, if it got out (Campaign::Overnight).
  has_one :rumour, dependent: :nullify

  normalizes :body, with: ->(body) { body.to_s.strip }
  normalizes :steps, with: ->(text) { text.to_s.strip.presence }
  normalizes :key, with: ->(key) { key.to_s.strip.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "").presence }

  validates :body, presence: true, length: { maximum: 500 }
  validates :key, format: { with: Flag::KEY_FORMAT, message: "must start with a letter: letters, digits and underscores" },
                  uniqueness: { scope: :campaign_id }, allow_nil: true
  validate { Clue.parse(steps).last.each { |problem| errors.add(:steps, problem) } }
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

  # Its steps, from the question to the last clue before the truth.
  def clues = Clue.list(steps)

  def chained? = steps.present?

  # The clues the party has found, in order.
  def found_clues = clues.first(found)

  # The step the party finds next, or nil (none left, or it's out).
  def next_clue = (clues[found] unless revealed?)

  # The question it starts from, or what it's about, for the lists.
  def question = clues.first&.text || body

  # The next step comes out, wherever it was found; with none left, the
  # secret itself. by: where or how ("In Tule", "Vivi's Ask Around").
  def find_clue!(by: nil)
    raise Refusal, "The party already knows that" if revealed?

    clue = next_clue or return reveal!(by: by)
    transaction do
      campaign.narrate("#{clue.question? ? 'A question' : 'A clue'}#{" (#{by})" if by}: #{clue}")
      update!(found: found + 1)
    end
    self
  end

  # Out at the table. by: how it came out ("Vivi's Scry"), if not the GM's telling.
  def reveal!(by: nil)
    raise Refusal, "The party already knows that" if revealed?

    transaction do
      said = campaign.narrate("#{by ? "#{by}: the" : 'The'} party learns: #{body.sub(/\.\z/, '')}.")
      # Revealed when it was said, so the recap finds it in that session.
      update!(revealed_at: said.created_at, revealed_by: by, found: clues.size)
    end
    self
  end

  # Put back, as if never learned (a GM's slip). Nothing is said at the table.
  def conceal!
    update!(revealed_at: nil, revealed_by: nil)
  end

  # The next secret to come out where the party is (a step of it, if it
  # comes out a step at a time): one about the place
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
    campaign.table_changed
    broadcast_replace_to campaign, :gm, target: "gm_secrets", partial: "campaigns/secrets/gm", locals: { campaign: campaign }
  end
end

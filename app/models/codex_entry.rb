# frozen_string_literal: true

# A page of a setting's lore: a faction, a faith, a stretch of history, a
# custom. The body is for the players (if the entry is public); the GM notes
# never are. The language model reads the codex when it drafts, so what it
# suggests belongs to the setting.
class CodexEntry < ApplicationRecord
  CATEGORIES = %w[Faction Faith History Region People Custom Rumour].freeze

  belongs_to :world

  normalizes :title, with: ->(title) { title.to_s.strip }
  normalizes :category, with: ->(category) { category.to_s.strip.presence }

  validates :title, presence: true, uniqueness: { scope: :world_id }, length: { maximum: 120 }
  validates :body, :gm_notes, length: { maximum: 20_000 }

  scope :in_order, -> { order(Arel.sql("COALESCE(category, '')"), :title) }
  scope :shown_to_players, -> { where(public: true) }
end

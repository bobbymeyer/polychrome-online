# frozen_string_literal: true

# What the party does becomes part of the world. A deed starts a rumour
# where it happened, carrying its sway: every town the news reaches thinks
# a little better, or worse, of the party (Location::Town#reputation). The
# party hears about themselves on arriving somewhere the story got to
# first. Beating an antagonist for good and clearing a dungeon are deeds
# by themselves; the GM records the rest.
module Campaign::Deeds
  extend ActiveSupport::Concern

  included do
    has_many :deeds, dependent: :delete_all
  end

  def record_deed!(body, at: current_node, sway: 0, kind: "gm")
    transaction do
      deed = deeds.create!(body: body, map_node: at, day: day, sway: sway.to_i, kind: kind)
      start_rumour!(body, at: at, sway: deed.sway, deed: deed) if at
      deed
    end
  end

  # The names of those who did it: "Rook, Lenna and Faris".
  def party_names(characters = self.characters.order(:created_at))
    names = characters.map(&:name)
    names.empty? ? "The party" : names.to_sentence
  end
end

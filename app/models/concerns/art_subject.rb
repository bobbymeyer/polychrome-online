# frozen_string_literal: true

# A speaker as the subject of their portraits (docs/HANDOFF.md §8): their own
# specifics and LoRAs, shared by every expression.
module ArtSubject
  extend ActiveSupport::Concern

  def art_loras=(value)
    super(ArtDirection.loras(value))
  end

  def art_world
    campaign.world
  end

  # Who they are, for every expression: name, what they are, and what they
  # look like. Never an NPC's description: that is the GM's private notes.
  def art_subject
    what = is_a?(Character) ? "a #{job.name}" : title
    ArtDirection.join_prompt(name, what, art_notes)
  end
end

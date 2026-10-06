# frozen_string_literal: true

# A speaker's full-body figure, for the stage (Beat): one per NPC or
# character, standing in a scene's beat where their portrait would. Uploaded
# in the speaker's form. A character without one stands as their archetype's
# figure; an NPC who fights as a Bestiary entry, as that creature.
class Sprite < ApplicationRecord
  belongs_to :owner, polymorphic: true
  has_one_attached :image

  validates :owner_type, inclusion: { in: Portrait::OWNER_TYPES }
end

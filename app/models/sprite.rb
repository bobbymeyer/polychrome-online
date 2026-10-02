# frozen_string_literal: true

# A speaker's full-body figure, for the stage (Beat): one per NPC or
# character, standing in a scene's beat where their portrait would. Uploaded
# in the speaker's form, or generated like a portrait (§8): the speaker is
# the subject, framed full body with the background taken off, and the
# first candidate starts from the neutral portrait's seed so it's the same
# face. A character without one stands as their archetype's figure; an NPC
# who fights as a Bestiary entry, as that creature.
class Sprite < ApplicationRecord
  belongs_to :owner, polymorphic: true
  has_one_attached :image

  validates :owner_type, inclusion: { in: Portrait::OWNER_TYPES }

  include Artwork

  def art_kind = "sprite"
  def art_title = "#{owner.name}'s sprite"
  def art_world = owner.art_world
  def art_stream = owner
  def art_filename(seed) = "#{owner.name.parameterize}-sprite-#{seed}.png"
  def art_subject_label = owner.name
  def art_subject = owner.art_subject
  def art_subject_loras = owner.art_loras
  def art_subject_model = owner.art_model
  def art_seed_hint = owner.portraits.find_by(expression: "neutral")&.image_seed
end

# frozen_string_literal: true

# A location mode's picture (§8). Made like a portrait's expression: the
# place's Gazetteer entry is the subject, and the mode's art words are one
# more layer after it ("on fire, thick smoke, ash falling"). The first
# candidate starts from the entry's own seed, so the burning city is still
# recognisably the city.
class ModeArt < ApplicationRecord
  belongs_to :location
  belongs_to :location_mode
  has_one_attached :image

  validates :location_mode, uniqueness: true

  include Artwork

  def mode = location_mode
  delegate :key, to: :location_mode, prefix: :mode

  def template = location.location_template

  def art_kind = "location_template"
  def art_title = "#{location.name} (#{mode.name})"
  def art_world = location.campaign.world
  def art_stream = location
  def art_filename(seed) = "#{location.name.parameterize}-#{mode_key.dasherize}-#{seed}.png"
  def art_subject_label = template.name
  def art_subject = template.art_subject
  def art_subject_loras = template.art_loras
  def art_subject_model = template.art_model
  def art_seed_hint = template.image_seed

  def art_detail
    { label: mode.name, prompt: mode.art.presence || mode.name.downcase }
  end
end

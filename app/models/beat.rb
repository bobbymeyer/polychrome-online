# frozen_string_literal: true

# One beat of a scene (Scene): who speaks and what they say (or narration,
# or a choice put to the table), what the stage shows behind them, who
# stands on it, and a cue or a change of music as it lands. The GM writes
# them in prep, in order, and steps through them at the table; everyone's
# stage shows the same beat (campaigns/tables/_scene).
#
# The backdrop is a place on the map (its picture, as it is now), a panel
# made for this beat (its own image, generated like a mode's picture: the
# place as the subject and this beat's words as one more layer), black, or
# whatever the beat before left there ("keep").
class Beat < ApplicationRecord
  KINDS = %w[say choice].freeze
  BACKDROPS = %w[keep place panel black].freeze
  SIDES = %w[left right].freeze
  SPEAKER_TYPES = %w[Npc Character].freeze

  belongs_to :scene
  belongs_to :speaker, polymorphic: true, optional: true
  belongs_to :map_node, optional: true
  has_one_attached :image

  # Its panel (§8): generated and picked like any entry's image.
  include Artwork

  normalizes :text, with: ->(text) { text.to_s.strip }
  normalizes :expression, :cue, :music, :flag_key, with: ->(value) { value.presence }

  validates :kind, inclusion: { in: KINDS }
  validates :backdrop, inclusion: { in: BACKDROPS }
  validates :speaker_type, inclusion: { in: SPEAKER_TYPES }, allow_nil: true
  validates :expression, inclusion: { in: Portrait::EXPRESSIONS }, allow_nil: true
  validates :cue, inclusion: { in: Message::CUES }, allow_nil: true
  validates :music, inclusion: { in: Campaign::MUSIC_CHOICES + %w[follow] }, allow_nil: true
  validates :text, length: { maximum: 2000 }
  validate :everyone_is_at_this_table
  validate :says_or_shows_something
  validate :choice_has_options

  before_validation { self.position ||= (scene.beats.maximum(:position) || -1) + 1 if scene }

  scope :in_order, -> { order(:position, :id) }

  delegate :campaign, to: :scene

  def choice? = kind == "choice"
  def narration? = speaker.nil? && !choice?
  def says? = text.present? && !choice?

  # "? Trust Cid | Refuse -> trusted_cid" as a beat.
  def self.choice_from(text)
    choice = Message.parse_choice(text) or return
    { "kind" => "choice", "text" => nil, "options" => choice[:options], "flag_key" => choice[:flag] }
  end

  # Who stands on the stage: [{ "type", "id", "side", "expression" }], the
  # speaker among them (lit) even if they weren't placed.
  def figures=(rows)
    rows = rows.is_a?(Hash) ? rows.values : Array(rows)
    super(rows.filter_map do |row|
      row = row.to_h.stringify_keys
      next unless SPEAKER_TYPES.include?(row["type"].to_s) && row["id"].present? && SIDES.include?(row["side"].to_s)

      { "type" => row["type"], "id" => row["id"].to_i, "side" => row["side"],
        "expression" => (Portrait::EXPRESSIONS.include?(row["expression"].to_s) ? row["expression"] : "neutral") }
    end)
  end

  # [{ "who" => Npc or Character, "side", "expression", "speaking" => bool }]
  def on_stage
    people = campaign.npcs.index_by(&:id).transform_keys { |id| "Npc:#{id}" }
                     .merge(campaign.characters.index_by(&:id).transform_keys { |id| "Character:#{id}" })
    placed = figures.filter_map do |f|
      who = people["#{f['type']}:#{f['id']}"] or next
      { "who" => who, "side" => f["side"], "expression" => f["expression"], "speaking" => who == speaker }
    end
    if speaker && placed.none? { |f| f["speaking"] }
      # The speaker takes the emptier side.
      side = placed.count { |f| f["side"] == "left" } > placed.count { |f| f["side"] == "right" } ? "right" : "left"
      placed << { "who" => speaker, "side" => side, "expression" => expression || "neutral", "speaking" => true }
    end
    placed.map { |f| f["speaking"] ? f.merge("expression" => expression || f["expression"]) : f }
  end

  # The stage behind this beat, this beat's own or the last one set before
  # it: { "kind" => "place", "node" => MapNode } | { "kind" => "panel",
  # "beat" => Beat } | { "kind" => "black" } | nil (the table as usual).
  def effective_backdrop
    beat = self
    loop do
      case beat.backdrop
      when "place" then return { "kind" => "place", "node" => beat.map_node } if beat.map_node
      when "panel" then return { "kind" => "panel", "beat" => beat }
      when "black" then return { "kind" => "black" }
      end
      beat = scene.beats.in_order.to_a.take_while { |b| b.position < beat.position }.last or return nil
    end
  end

  # The picture behind it, if the backdrop has one.
  def backdrop_image
    behind = effective_backdrop or return nil
    case behind["kind"]
    when "place" then behind["node"].location&.picture
    when "panel" then behind["beat"].image if behind["beat"].image.attached?
    end
  end

  # How long it is left up when the scene plays on by itself: the box types
  # it out (dialogue_controller), then holds it to be read.
  def seconds
    (3.2 + (text.to_s.length * 0.06)).round(1)
  end

  # The same shape Scene#lines has always had, for playing and summing up.
  def line
    return { "choice" => { options: options, flag: flag_key } } if choice?

    { "speaker" => speaker, "expression" => expression, "text" => text }
  end

  # --- the panel (Artwork) -----------------------------------------------------
  # The place behind the beat is the subject, as a mode's picture has the
  # place; this beat's words are the layer after it. Without a place, the
  # words are the subject.

  def art_kind = "beat"
  def art_title = "#{scene.name}, beat #{position + 1}"
  def art_world = campaign.world
  def art_stream = scene
  def art_filename(seed) = "#{scene.name.parameterize}-#{position + 1}-#{seed}.png"
  def art_subject_label = panel_template&.name || scene.name
  def art_subject = panel_template ? panel_template.art_subject : ArtDirection.join_prompt(scene.name, panel_words)
  def art_subject_loras = panel_template ? panel_template.art_loras : art_loras
  def art_subject_model = panel_template ? panel_template.art_model : art_model
  def art_detail = (panel_template ? { label: "This beat", prompt: panel_words } : nil)
  def art_seed_hint = panel_template&.image_seed

  # What the panel shows, in the GM's words (art_notes), else the line itself.
  def panel_words = art_notes.presence || text.presence || scene.name

  # The place this beat stands in, if a place was set on or before it.
  def panel_template
    behind = scene.beats.in_order.to_a.select { |b| b.position <= position }.reverse.find { |b| b.backdrop == "place" && b.map_node }
    behind&.map_node&.location&.location_template
  end

  private

  def everyone_is_at_this_table
    errors.add(:speaker, "isn't in this campaign") if speaker && speaker.campaign_id != campaign.id
    errors.add(:map_node, "isn't on this campaign's map") if map_node && map_node.campaign_id != campaign.id
    errors.add(:backdrop, "needs a place") if backdrop == "place" && map_node.nil?
  end

  # A beat that says nothing can still change the stage.
  def says_or_shows_something
    return if choice? || text.present? || backdrop != "keep" || figures.any? || music.present?

    errors.add(:text, "is empty: say something, or change what the stage shows")
  end

  def choice_has_options
    return unless choice?

    errors.add(:options, "needs two options or more: “? Trust Cid | Refuse -> trusted_cid”") if options.size < 2 || options.size > Message::Choice::MAX_OPTIONS
  end
end

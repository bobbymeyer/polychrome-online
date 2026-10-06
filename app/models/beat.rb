# frozen_string_literal: true

# One step of a scene (Scene), written in prep and played at the table in
# order: a line said (by someone from the cast, one of the party, or the
# narrator, with an expression and maybe a jingle); a choice put to the
# table; a change of backdrop (a place on the map as it is now, a panel
# made for this step, or black); a sprite change (someone enters the stage
# on a side with a face, changes it, or leaves); a change of music; or an
# effect (a name for now: the stage carries it, nothing plays it yet). The
# stage at any step is folded from the steps before it (Scene#stage_at).
#
# Lines and choices are what the table stops on; the rest happen on the
# way to the next line (Scene#advance!).
class Beat < ApplicationRecord
  KINDS = %w[say choice backdrop sprite music fx].freeze
  WAITING = %w[say choice].freeze
  BACKDROPS = %w[place panel black].freeze
  ACTIONS = %w[enter change leave].freeze
  SIDES = %w[left right].freeze
  SPEAKER_TYPES = %w[Npc Character].freeze
  LABELS = { "say" => "Line", "choice" => "Choice", "backdrop" => "Backdrop", "sprite" => "Sprite", "music" => "Music", "fx" => "Effect" }.freeze
  # How a change comes on: a quick fade unless said otherwise.
  TRANSITIONS = { "fade" => "Quick fade", "slow" => "Slow fade", "slide" => "Slide in", "cut" => "Cut" }.freeze
  TRANSITIONS_FOR = { "backdrop" => %w[fade slow cut], "sprite" => %w[fade slow slide cut], "music" => %w[fade cut] }.freeze

  belongs_to :scene
  belongs_to :speaker, polymorphic: true, optional: true
  belongs_to :map_node, optional: true
  has_one_attached :image

  # Its panel (§8): generated and picked like any entry's image.
  include Artwork

  normalizes :text, with: ->(text) { text.to_s.strip }
  normalizes :expression, :cue, :music, :flag_key, :action, :fx, with: ->(value) { value.to_s.strip.presence }

  validates :kind, inclusion: { in: KINDS }
  validates :speaker_type, inclusion: { in: SPEAKER_TYPES }, allow_nil: true
  validates :expression, inclusion: { in: Portrait::EXPRESSIONS }, allow_nil: true
  validates :cue, inclusion: { in: Message::CUES }, allow_nil: true
  validates :text, length: { maximum: 2000 }
  validate :everyone_is_at_this_table
  validate :whole_of_its_kind

  before_validation { self.position ||= (scene.beats.maximum(:position) || -1) + 1 if scene }

  scope :in_order, -> { order(:position, :id) }

  delegate :campaign, to: :scene

  def choice? = kind == "choice"
  def say? = kind == "say"
  def says? = say? && text.present?
  # The table stops on it; the rest happen on the way to the next one.
  def waits? = WAITING.include?(kind)
  def label = LABELS.fetch(kind)
  # A change of the stage (not a line or a choice): it has a transition.
  def changes_stage? = TRANSITIONS_FOR.key?(kind)
  def transitions = TRANSITIONS.slice(*TRANSITIONS_FOR.fetch(kind, []))

  # "? Trust Cid | Refuse -> trusted_cid" as a step.
  def self.choice_from(text)
    choice = Message.parse_choice(text) or return
    { "kind" => "choice", "text" => nil, "options" => choice[:options], "flag_key" => choice[:flag] }
  end

  # A sprite step's one figure: { "type", "id", "side", "expression" }.
  def figures=(rows)
    rows = rows.is_a?(Hash) ? rows.values : Array(rows)
    super(rows.filter_map do |row|
      row = row.to_h.stringify_keys
      next unless SPEAKER_TYPES.include?(row["type"].to_s) && row["id"].present?

      { "type" => row["type"], "id" => row["id"].to_i, "side" => (SIDES.include?(row["side"].to_s) ? row["side"] : "left"),
        "expression" => (Portrait::EXPRESSIONS.include?(row["expression"].to_s) ? row["expression"] : "neutral") }
    end.first(1))
  end

  def figure = figures.first

  # Who a sprite step is about (Npc or Character), or nil.
  def who
    f = figure or return nil
    campaign.public_send(f["type"].underscore.pluralize).find_by(id: f["id"])
  end

  # The stage as it is at this step (Scene#stage_at): who stands on it,
  # [{ "who", "side", "expression", "speaking" }], the speaker of a line
  # among them (lit) even if nobody put them there.
  def on_stage
    placed = scene.stage_at(self)["figures"].map { |f| f.merge("speaking" => f["who"] == speaker) }
    if say? && speaker && placed.none? { |f| f["speaking"] }
      # The speaker takes the emptier side.
      side = placed.count { |f| f["side"] == "left" } > placed.count { |f| f["side"] == "right" } ? "right" : "left"
      placed << { "who" => speaker, "side" => side, "expression" => expression || "neutral", "speaking" => true }
    end
    placed.map { |f| f["speaking"] && expression ? f.merge("expression" => expression) : f }
  end

  # The backdrop at this step: { "kind" => "place", "node" => MapNode } |
  # { "kind" => "panel", "beat" => Beat } | { "kind" => "black" } | nil
  # (the table as usual).
  def effective_backdrop = scene.stage_at(self)["backdrop"]

  # The picture behind it, if the backdrop has one.
  def backdrop_image
    behind = effective_backdrop or return nil
    case behind["kind"]
    when "place" then behind["node"].location&.picture
    when "panel" then behind["beat"].image if behind["beat"].image.attached?
    end
  end

  # The effect at this step, if the last effect step is still the latest word (placeholder).
  def effect = scene.stage_at(self)["fx"]

  # Who left on the way to this step, [{ "who", "side", "expression", "transition" }]: they go
  # out as the step comes on, then they're gone.
  def leaving = scene.stage_at(self)["leaving"]

  # The transition the backdrop came on with, if it changed on the way to this step.
  def fresh_backdrop = scene.stage_at(self)["fresh"]["backdrop"]

  # What this step sets, for the stage fold (Scene#stage_at). A change marks what it changed
  # with its transition ("arrived" on a figure, "fresh" on the stage, the leaving kept aside);
  # the fold clears the marks once the table has stopped on a line, so each change plays once.
  def apply_to(state)
    case kind
    when "backdrop"
      state["backdrop"] = case backdrop
      when "place" then map_node && { "kind" => "place", "node" => map_node }
      when "panel" then { "kind" => "panel", "beat" => self }
      when "black" then { "kind" => "black" }
      end
      state["fresh"]["backdrop"] = transition
    when "sprite"
      f = figure or return state
      person = who or return state
      state["figures"] = state["figures"].reject { |g| g["who"] == person }
      if action == "leave"
        state["leaving"] = state["leaving"].reject { |g| g["who"] == person } << { "who" => person, "side" => f["side"], "expression" => f["expression"], "transition" => transition }
      else
        state["leaving"] = state["leaving"].reject { |g| g["who"] == person }
        state["figures"] << { "who" => person, "side" => f["side"], "expression" => f["expression"], "arrived" => transition }
      end
    when "fx"
      state["fx"] = fx
    end
    state
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

  # A music step's track, named: a kind of scene, silence, or one of the world's by name.
  def music_name
    return music unless campaign.world.music_track_choice?(music)

    campaign.world.tracks.find { |track| "track:#{track.id}" == music }&.name || music
  end

  # One line for the sequencer and the summary.
  def describe
    case kind
    when "say" then "#{speaker&.name || 'Narrator'}: #{text}"
    when "choice" then "The party decides: #{options.join(' / ')}"
    when "backdrop" then { "place" => "Backdrop: #{map_node&.name || 'a place'}", "panel" => "Backdrop: a panel", "black" => "Backdrop: black" }[backdrop] + how
    when "sprite" then "#{who&.name || 'Someone'} #{action == 'leave' ? 'leaves' : "#{action == 'enter' ? 'enters' : 'turns'} #{figure&.dig('side')}, #{figure&.dig('expression')}"}#{how}"
    when "music" then "Music: #{music == 'follow' ? 'follow the place' : music_name}#{how}"
    when "fx" then "Effect: #{fx}"
    end
  end

  # ", slow fade" and the like after a change; a quick fade goes without saying.
  def how = transition == "fade" ? "" : ", #{TRANSITIONS.fetch(transition, transition).downcase}"

  # --- the panel (Artwork) -----------------------------------------------------
  # The place behind the step is the subject, as a mode's picture has the
  # place; this step's words are the layer after it. Without a place, the
  # words are the subject.

  def art_kind = "beat"
  def art_title = "#{scene.name}, step #{position + 1}"
  def art_world = campaign.world
  def art_stream = scene
  def art_filename(seed) = "#{scene.name.parameterize}-#{position + 1}-#{seed}.png"
  def art_subject_label = panel_template&.name || scene.name
  def art_subject = panel_template ? panel_template.art_subject : ArtDirection.join_prompt(scene.name, panel_words)
  def art_subject_loras = panel_template ? panel_template.art_loras : art_loras
  def art_subject_model = panel_template ? panel_template.art_model : art_model
  def art_detail = (panel_template ? { label: "This step", prompt: panel_words } : nil)
  def art_seed_hint = panel_template&.image_seed

  # What the panel shows, in the GM's words (art_notes), else the line before it, else the scene's name.
  def panel_words = art_notes.presence || scene.beats.in_order.to_a.reverse.find { |b| b.position <= position && b.says? }&.text.presence || scene.name

  # The place this step stands in: the last place set on or before it.
  def panel_template
    behind = scene.beats.in_order.to_a.reverse.find { |b| b.position <= position && b.kind == "backdrop" && b.backdrop == "place" && b.map_node }
    behind&.map_node&.location&.location_template
  end

  private

  def everyone_is_at_this_table
    errors.add(:speaker, "isn't in this campaign") if speaker && speaker.campaign_id != campaign.id
    errors.add(:map_node, "isn't on this campaign's map") if map_node && map_node.campaign_id != campaign.id
  end

  def whole_of_its_kind
    case kind
    when "say" then errors.add(:text, "is empty: say something") if text.blank?
    when "choice"
      errors.add(:options, "needs two options or more: “? Trust Cid | Refuse -> trusted_cid”") if options.size < 2 || options.size > Message::Choice::MAX_OPTIONS
    when "backdrop"
      errors.add(:backdrop, "must be a place, a panel or black") unless BACKDROPS.include?(backdrop)
      errors.add(:backdrop, "needs a place") if backdrop == "place" && map_node.nil?
    when "sprite"
      errors.add(:action, "must be enter, change or leave") unless ACTIONS.include?(action)
      errors.add(:figures, "needs someone from the cast or the party") if who.nil?
    when "music" then errors.add(:music, "must be one of the table's tracks, silence, or follow") unless (Campaign::MUSIC_CHOICES + %w[follow]).include?(music) || campaign.world.music_track_choice?(music)
    when "fx" then errors.add(:fx, "needs a name") if fx.blank?
    end
    if changes_stage? && !transitions.key?(transition)
      errors.add(:transition, "must be #{transitions.values.map(&:downcase).to_sentence(last_word_connector: ' or ')}")
    end
  end
end

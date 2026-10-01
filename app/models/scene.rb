# frozen_string_literal: true

# A scene the GM prepares before the session and plays at the table: a
# sequence of beats (Beat), each a line said (by someone from the cast, one
# of the party, or the narrator), what the stage shows behind it, who stands
# on the stage, and a cue; then it ends, in a battle, with a place revealed
# on the map, or with a place changed (its ending is an Outcome, as a full
# clock's is).
#
# At the table the GM puts the scene on the stage (#start!) and steps beat
# to beat (#advance!), or lets it play on at reading pace (#play_on!,
# SceneStepJob); everyone's stage shows the same beat. The last beat can
# put a choice to the table.
#
# Beats are written one by one in prep, or in bulk as a script that reads
# like a play, one line each (#script, turned into beats on save):
#
#   Cid (worried): The airship won't hold.
#   The wind picks up.
#   Narrator: A shadow crosses the moon.
#   ? Trust Cid | Refuse -> trusted_cid
class Scene < ApplicationRecord
  ENDINGS = %w[none battle reveal mode].freeze
  LINE = /\A(?<name>[^:()]+?)\s*(?:\((?<expression>[^)]*)\))?\s*:\s*(?<text>.+)\z/
  # Longer than this before the colon, it's narration that has a colon in it.
  NAME_WORDS = 3

  include CampaignPages

  belongs_to :campaign
  belongs_to :map_node, optional: true
  # A "mode" ending sets this mode off; without one, the place goes back
  # to how it was.
  belongs_to :mode, optional: true
  has_many :beats, -> { in_order }, dependent: :destroy

  normalizes :name, with: ->(name) { name.to_s.strip }
  normalizes :script, with: ->(script) { script.to_s.strip.presence }

  validates :name, presence: true
  validates :ending, inclusion: { in: ENDINGS }
  validate :script_reads
  validate :ending_is_complete

  after_save :import_script!, if: -> { script.present? }

  scope :in_order, -> { order(Arel.sql("played_at IS NOT NULL"), :created_at, :id) }

  def played?
    played_at.present?
  end

  # On the campaign's stage right now (Campaign#staged_scene).
  def staged?
    cursor.present? && campaign.staged_scene_id == id
  end

  def current_beat
    beats[cursor] if cursor
  end

  def last_beat? = cursor && cursor >= beats.size - 1

  # The beats, and the script's lines not yet turned into beats, as
  # [{ "speaker" => Npc, Character or nil, "expression", "text", "problem" }]
  # or [{ "choice" => { options:, flag: } }].
  def lines
    beats.map(&:line) + script_lines
  end

  # The script's lines, read as a scene reads them (not beats yet).
  def script_lines
    return [] if script.blank?

    cast = campaign.npcs.to_a + campaign.characters.to_a
    script.lines.map(&:strip).reject(&:empty?).map { |raw| read(raw, cast) }
  end

  # The script becomes beats, one a line, after the beats already there;
  # the script box is then empty for the next lines.
  def import_script!
    transaction do
      script_lines.each do |line|
        attrs = line["choice"] ? { "kind" => "choice", "options" => line["choice"][:options], "flag_key" => line["choice"][:flag] } :
                                 { "speaker" => line["speaker"], "expression" => line["expression"], "text" => line["text"] }
        beats.create!(attrs)
      end
      update_columns(script: nil)
    end
    beats.reset
  end

  # One line of a script, read as a scene reads it: a speaker's (with an
  # expression), the narrator's, or narration with a colon in it ("Tsukiura
  # Station, 0:09."). A boss's entrance is read the same way. The cast is
  # whoever may speak: the NPCs, and at a scene the party too.
  #   { "speaker" => Npc, Character or nil, "expression", "text", "problem" }
  def self.read_line(raw, cast)
    match = LINE.match(raw)
    return { "speaker" => nil, "expression" => nil, "text" => raw } unless match

    name = match[:name].strip
    expression = match[:expression].to_s.strip.downcase.presence
    line = { "speaker" => nil, "expression" => expression, "text" => match[:text].strip }
    return line if name.casecmp?("narrator")

    who = cast.find { |n| n.name.casecmp?(name) }
    return line.merge("speaker" => who) if who
    # Not a name: too long, or a time or a place and a time ("Tsukiura Station, 0:09.").
    return { "speaker" => nil, "expression" => nil, "text" => raw } if name.split.size > NAME_WORDS || name.match?(/[\d,]/) || line["text"].match?(/\A\d/)

    line.merge("problem" => "#{name} isn't in the cast. Add them as an NPC, or start the line with “Narrator:”.")
  end

  # --- on the stage --------------------------------------------------------------

  # The scene goes on the campaign's stage, at its first beat. One scene at
  # a time: another still up is taken down first.
  def start!
    raise Refusal, "#{name} has no beats to play" if beats.empty?

    outcome&.can_happen!(campaign)
    transaction do
      campaign.staged_scene&.take_down!
      update!(cursor: 0, auto: false)
      campaign.update!(staged_scene: self)
      show!(beats.first)
    end
    campaign.table_changed
  end

  # The next beat, or, past the last, the ending. Returns the battle a
  # battle ending starts.
  def advance!
    raise Refusal, "#{name} isn't on the stage" unless staged?

    return finish! if last_beat?

    transaction do
      update!(cursor: cursor + 1)
      show!(current_beat)
    end
    campaign.table_changed
    nil
  end

  # The beats go on by themselves, at reading pace (SceneStepJob), until a
  # choice, the end, or the GM pauses.
  def play_on!
    raise Refusal, "#{name} isn't on the stage" unless staged?

    update!(auto: true)
    schedule_step!
    campaign.table_changed
  end

  def pause!
    update!(auto: false)
    campaign.table_changed
  end

  # Off the stage without its ending; what was said stays said.
  def stop!
    transaction { take_down! }
    campaign.table_changed
  end

  # The whole scene at once: every beat, then the ending (how a scene used
  # to be played, and still is by anything that isn't the GM's hand).
  def play!
    start!
    battle = nil
    battle = advance! until battle || !staged?
    battle
  end

  # How it ends, as the game's outcomes (Outcome): a fight, a place
  # revealed, a place set in a mode or back to how it was. Nil for none.
  def outcome
    case ending
    when "battle" then Outcome.of("battle", target: { "name" => name, "monsters" => encounter })
    when "reveal" then map_node && Outcome.of("reveal", target: { "node" => map_node.id })
    when "mode" then map_node && Outcome.of("mode", target: { "node" => map_node.id, "mode" => mode&.key })
    end
  end

  def summary
    all = lines
    said = all.reject { |l| l["choice"] }
    parts = [ ActionController::Base.helpers.pluralize(said.size, "beat") ]
    parts << "then a choice: #{all.last['choice'][:options].join(' / ')}" if all.last&.dig("choice")
    parts << "then a battle: #{campaign.describe_encounter(encounter)}" if ending == "battle"
    parts << "then #{map_node&.name || 'a place'} appears on the map" if ending == "reveal"
    if ending == "mode"
      parts << (mode ? "then #{map_node&.name}: #{mode.name}" : "then #{map_node&.name} goes back to how it was")
    end
    parts.join(", ")
  end

  # The next beat is due after this one has been read (SceneStepJob).
  def schedule_step!
    SceneStepJob.set(wait: current_beat.seconds.seconds).perform_later(self, cursor)
  end

  # Off the stage, as it was (inside the caller's transaction).
  def take_down!
    update!(cursor: nil, auto: false)
    campaign.update!(staged_scene: nil) if campaign.staged_scene_id == id
  end

  private

  # A beat lands at the table: its line goes out (through the dialogue box:
  # a scene's lines always do, the party's included), with its cue; its
  # music plays; the stage shows it (Campaign::Broadcasts, table_scene).
  def show!(beat)
    if beat.choice?
      Message.choice(campaign, options: beat.options, flag: beat.flag_key).tap { |m| m.data = { "scene" => id } }.save!
      update!(auto: false) # the table's turn
    elsif beat.says?
      campaign.messages.create!(speaker: beat.speaker, expression: beat.expression, body: beat.text, cue: beat.cue, data: { "scene" => id })
    end
    campaign.update!(music: beat.music == "follow" ? nil : beat.music) if beat.music
  end

  # The last beat has been read: the ending plays, and the stage is the
  # table's again. A battle starts last, so everyone reads the scene before
  # the stage takes them there (stage.js waits for the dialogue box).
  def finish!
    transaction do
      unless ending == "battle"
        said = outcome&.apply!(campaign, by: name)
        campaign.narrate(said) if said
      end
      take_down!
      update!(played_at: Time.current)
    end
    campaign.table_changed
    return unless ending == "battle"

    outcome.apply!(campaign, by: name)
    campaign.battles.order(:id).last # the fight it started
  end

  def read(raw, cast)
    if raw.start_with?("?")
      choice = Message.parse_choice(raw)
      return { "choice" => choice } if choice

      return { "text" => raw, "problem" => "A choice needs two options or more: “? Trust Cid | Refuse -> trusted_cid”." }
    end

    self.class.read_line(raw, cast)
  end

  def script_reads
    all = lines
    all.each do |line|
      errors.add(:script, line["problem"]) if line["problem"]
      if line["choice"] && line != all.last
        errors.add(:script, "can only end on a choice, with nothing after it: the next scene can follow what the party chose")
      elsif line["choice"] && ending != "none"
        errors.add(:ending, "can't follow a choice: a scene that ends on a choice leaves what happens next to the party. " \
                            "Set “When the last line is said” to Nothing, or make the fight a scene of its own")
      end
      if line["expression"] && !Portrait::EXPRESSIONS.include?(line["expression"])
        errors.add(:script, "“#{line['expression']}” isn't an expression. Use one of #{Portrait::EXPRESSIONS.to_sentence(last_word_connector: ' or ')}.")
      end
    end
    errors.add(:script, "is empty, and the scene has no ending") if all.empty? && ending == "none"
  end

  def ending_is_complete
    case ending
    when "battle"
      known = campaign.world.monsters.where(slug: encounter.keys).pluck(:slug)
      errors.add(:encounter, "needs a monster from the Bestiary") if encounter.empty? || (encounter.keys - known).any?
    when "reveal"
      errors.add(:map_node, "must be a place on this campaign's map") unless map_node && map_node.campaign_id == campaign_id
    when "mode"
      if map_node&.campaign_id != campaign_id
        errors.add(:map_node, "must be a place on this campaign's map")
      elsif mode && mode.map_node_id != map_node.id
        errors.add(:mode, "isn't one of #{map_node.name}'s modes")
      end
    end
  end
end

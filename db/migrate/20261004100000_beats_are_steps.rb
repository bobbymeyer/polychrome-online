# frozen_string_literal: true

# A beat did several things at once: a line, the backdrop behind it, who
# stands on the stage, the music. It is one step now: a line, a choice, a
# backdrop change, a sprite change (someone enters, leaves or changes
# face), a music change, or an effect (a placeholder for now), each its
# own row in the sequencer, and the stage is folded from the steps before.
# Beats already written are split: a backdrop or music set on a line
# becomes its own step before it, and each figure placed on it a sprite
# step; the row with the panel image stays the backdrop step.
class BeatsAreSteps < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :beats, :action, :string
    add_column :beats, :fx, :string

    Beat.reset_column_information
    Scene.reset_column_information
    Scene.find_each do |scene|
      steps = []
      scene.beats.reorder(:position, :id).each do |beat|
        stage_set = beat.backdrop != "keep"
        figures = Array(beat.figures)
        music = beat.music
        line = beat.attributes.slice("kind", "speaker_type", "speaker_id", "expression", "text", "cue", "options", "flag_key")
        if stage_set
          # The row keeps its panel (image and art); the line moves to a new row after it.
          steps << [ :keep, beat, { "kind" => "backdrop", "speaker_type" => nil, "speaker_id" => nil, "expression" => nil, "text" => nil, "cue" => nil, "music" => nil, "figures" => [], "options" => [], "flag_key" => nil } ]
        end
        figures.each { |f| steps << [ :new, { "kind" => "sprite", "action" => "enter", "figures" => [ f ], "backdrop" => "keep" } ] }
        steps << [ :new, { "kind" => "music", "music" => music, "backdrop" => "keep" } ] if music
        steps << (stage_set ? [ :new, line.merge("backdrop" => "keep") ] : [ :keep, beat, { "music" => nil, "figures" => [] } ])
      end
      steps.each_with_index do |(how, *rest), i|
        if how == :keep
          beat, changes = rest
          beat.update_columns(changes.merge("position" => i + 1000)) # out of the way of the unique-ish order first
        else
          scene.beats.create!(rest.first.merge("position" => i + 1000))
        end
      end
      scene.beats.reorder(:position, :id).each_with_index { |beat, i| beat.update_columns(position: i) }
    end
  end

  def down
    remove_column :beats, :fx
    remove_column :beats, :action
  end
end

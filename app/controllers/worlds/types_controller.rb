# frozen_string_literal: true

# A world's damage types (TypeChart): the chart for everyone, and the editor
# for whoever may change the world. A save goes through TypeChange, which
# sends a removed type's uses where the author says.
class Worlds::TypesController < ApplicationController
  include WorldScoped
  before_action :require_world_editor, only: %i[edit update]

  def show
    @chart = @world.type_chart
  end

  def edit
    @uses = TypeChange.uses(@world)
  end

  def update
    change = TypeChange.new(@world, rows: posted_rows, sends: posted_sends, terrain: posted_terrain)
    if change.save
      redirect_to world_types_path(@world), notice: report(change)
    else
      @uses = TypeChange.uses(@world.reload)
      flash.now[:alert] = change.world.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_content
    end
  end

  private

  # The posted rows, in the form's order ("0", "1", …).
  def type_params
    JsonCasting.rows(params.permit(types: [ :slug, :name, :colour, :remove, :send_to, { shrugs_off: [] } ]).fetch(:types, [])).map(&:with_indifferent_access)
  end

  # The kept and added types, the plain one first. A new type's id comes
  # from its name.
  def posted_rows
    rows = type_params.filter_map do |row|
      next if row[:remove] == "1"

      slug = row[:slug].presence || row[:name].to_s.parameterize(separator: "_")
      next if slug.blank?

      against = TypeChart::PERCENTS.keys.map(&:to_s)
      chart = params.dig(:chart, slug)
      { "slug" => slug, "name" => row[:name].to_s.strip, "colour" => row[:colour].to_s,
        "shrugs_off" => Array(row[:shrugs_off]).compact_blank & Battle::STATUSES,
        "against" => (chart.respond_to?(:each_pair) ? chart.keys.to_h { |k| [ k.to_s, chart[k].to_s ] } : {})
                         .select { |_, v| against.include?(v) }.transform_values(&:to_i) }
    end
    plain = rows.find { |r| r["slug"] == params[:plain] }
    plain ? [ plain ] + (rows - [ plain ]) : rows
  end

  def posted_sends
    type_params.select { |row| row[:remove] == "1" && row[:slug].present? }.to_h { |row| [ row[:slug], row[:send_to] ] }
  end

  def posted_terrain
    terrain = params[:terrain]
    return unless terrain.respond_to?(:each_pair)

    EncounterTable::TERRAINS.to_h { |place| [ place, terrain[place].to_s ] }.compact_blank
  end

  def report(change)
    parts = [ "Types saved." ]
    change.moved.each { |type, names| parts << "Now #{@world.type_chart.name(type)}: #{names.uniq.to_sentence}." }
    parts << "Dropped #{change.dropped.to_sentence}." if change.dropped.any?
    parts.join(" ")
  end
end

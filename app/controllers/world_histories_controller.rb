# frozen_string_literal: true

# A setting's pocket history (Chronicle): rolled over its atlas, rerolled
# until it's right, and written into the codex, cast, atlas and fronts. Its
# GMs can read it; its editors roll and write it.
class WorldHistoriesController < ApplicationController
  before_action :set_world
  before_action :require_lore, only: :show
  before_action :require_world_editor, except: :show

  def show
    @chronicle = Chronicle.new(@world)
  end

  # Reroll, change the span, keep a family or let one go.
  def update
    chronicle = Chronicle.new(@world)
    notice = if params[:reroll]
      chronicle.reroll!
      "Rolled again."
    elsif params[:keep]
      chronicle.keep!(params[:keep])
      "Kept: it stays through rerolls."
    elsif params[:let_go]
      chronicle.let_go!(params[:let_go])
      "Let go: the next roll may lose it."
    else
      chronicle.set_years!(params[:years])
      "#{chronicle.years} years of history."
    end
    redirect_to world_history_path(@world), notice: notice, status: :see_other
  rescue Refusal => e
    redirect_to world_history_path(@world), alert: e.message, status: :see_other
  end

  # Write it into the canon.
  def create
    counts = Chronicle.new(@world).write!
    written = { codex: [ "codex page", "codex pages" ], figures: [ "person in the cast", "people in the cast" ],
                places: [ "place's past", "places' pasts" ], fronts: [ "front", "fronts" ] }
              .filter_map { |key, (one, many)| "#{counts[key]} #{counts[key] == 1 ? one : many}" if counts[key].positive? }
    redirect_to world_history_path(@world), notice: written.any? ? "Written in: #{written.to_sentence}." : "Nothing new to write in.", status: :see_other
  end

  # Take out what it wrote, less what's been changed since.
  def destroy
    Chronicle.new(@world).take_out!
    redirect_to world_history_path(@world), notice: "Taken out of the canon. Whatever you'd changed stays.", status: :see_other
  end

  private

  def set_world
    @world = World.find_by!(slug: params[:world_slug])
  end

  def require_lore
    forbid unless knows_the_lore?
  end
end

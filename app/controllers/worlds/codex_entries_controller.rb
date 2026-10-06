# frozen_string_literal: true

# A setting's codex (CodexEntry): its lore. Anyone can read the public
# pages; the GM-only ones, and every page's GM notes, are for its editors
# and GMs.
class Worlds::CodexEntriesController < ApplicationController
  include WorldScoped
  before_action :require_world_editor, except: %i[index show]
  before_action :set_entry, only: %i[show edit update destroy]

  def index
    @entries = readable.in_order
  end

  def show
    forbid unless @entry.public? || knows_the_lore?
  end

  def new
    @entry = @world.codex_entries.new(category: params[:category])
  end

  def create
    @entry = @world.codex_entries.new(entry_params)
    @entry.save ? redirect_to(world_codex_entry_path(@world, @entry), notice: "#{@entry.title} is in the codex.") : render(:new, status: :unprocessable_content)
  end

  def edit; end

  def update
    @entry.update(entry_params.merge(edited: true)) ? redirect_to(world_codex_entry_path(@world, @entry), notice: "#{@entry.title} saved.") : render(:edit, status: :unprocessable_content)
  end

  def destroy
    @entry.destroy!
    redirect_to world_codex_entries_path(@world), notice: "#{@entry.title} is out of the codex.", status: :see_other
  end

  private

  def set_entry
    @entry = @world.codex_entries.find(params[:id])
  end

  def readable
    knows_the_lore? ? @world.codex_entries : @world.codex_entries.shown_to_players
  end

  def entry_params
    params.expect(codex_entry: %i[title category body gm_notes public])
  end
end

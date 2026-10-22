# frozen_string_literal: true

# A world's edit log (BookRevision): the recent edits to its books, or one entry's, each with the way to put the entry
# back as it was before. For those who can change the books.
class Worlds::RevisionsController < ApplicationController
  include WorldScoped
  before_action :require_world_editor

  RECENT = 60

  def index
    @entry = find_entry
    @revisions = (@entry ? @entry.revisions : @world.book_revisions.newest_first).includes(:user, :record).limit(RECENT)
  end

  private

  def find_entry
    return unless params[:book].present? && params[:slug].present?

    book = World::Books::LIST.find { |candidate| candidate.key.to_s == params[:book] }
    book&.model&.include?(Revisable) ? book.entries(@world).find_by!(slug: params[:slug]) : raise(ActiveRecord::RecordNotFound)
  end
end

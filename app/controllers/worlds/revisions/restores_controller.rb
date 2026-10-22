# frozen_string_literal: true

# Puts an entry back as it was before an edit (BookRevision#restore!). The restoring is an edit too, so it is in the log.
class Worlds::Revisions::RestoresController < ApplicationController
  include WorldScoped
  before_action :require_world_editor

  def create
    revision = @world.book_revisions.find(params[:revision_id])
    entry = revision.restore!
    redirect_to polymorphic_path([ @world, World::Books.for(entry).key, entry ]), notice: "#{entry.name} is back as it was before that edit."
  rescue Refusal => refusal
    redirect_back_or_to world_revisions_path(@world), alert: refusal.message
  end
end

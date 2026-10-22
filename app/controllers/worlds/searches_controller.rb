# frozen_string_literal: true

# One search across a world's books by name or slug (World::Books). The codex, the atlas and the cast are left out: they
# hold the GM's side, which not everyone who reads the books may see. A single match goes straight to its page.
class Worlds::SearchesController < ApplicationController
  include WorldScoped

  PER_BOOK = 25

  def show
    @query = params[:q].to_s.strip
    found = @query.empty? ? [] : search(@query).select { |_, entries, _| entries.any? }
    if found.one? && found.first[2] == 1
      book, entries, = found.first
      return redirect_to polymorphic_path([ @world, book.key, entries.first ])
    end

    @results = found
  end

  private

  # [[book, entries (up to PER_BOOK), how many matched]] for every book.
  def search(query)
    like = "%#{World.sanitize_sql_like(query)}%"
    World::Books::LIST.map do |book|
      found = book.entries(@world).where("name LIKE :q ESCAPE '\\' OR slug LIKE :q ESCAPE '\\'", q: like).order(:name)
      [ book, found.limit(PER_BOOK).to_a, found.count ]
    end
  end
end

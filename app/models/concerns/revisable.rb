# frozen_string_literal: true

# A book entry that keeps what it was before each edit (BookRevision), a few at a time. For the entries that are one row:
# an archetype's learn table is rows of its own, which a snapshot of the entry would not bring back.
#
# Not kept: the slug (fixed for life), timestamps, and the picture (stored files aren't rows).
module Revisable
  extend ActiveSupport::Concern

  UNTRACKED = %w[id world_id slug created_at updated_at].freeze
  KEPT = 20

  included do
    has_many :revisions, -> { newest_first }, as: :record, class_name: "BookRevision", dependent: :delete_all
    after_update :keep_revision
  end

  private

  def keep_revision
    changed = saved_changes.keys - UNTRACKED
    return if changed.empty?

    before = attributes.except(*UNTRACKED).merge(changed.index_with { |name| saved_changes[name].first })
    revisions.create!(world_id: world_id, user: Current.user, snapshot: before, changed_fields: changed)
    revisions.where(id: revisions.offset(KEPT).ids).delete_all
  end
end

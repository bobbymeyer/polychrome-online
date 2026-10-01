# frozen_string_literal: true

# A commit remembers only the last save, and a transaction often saves a
# record twice: passing time saves the campaign again as the world moves on
# (the RNG state), a battle's end settles the party after the status. So a
# model that tells the table about some of its columns notes, at each save,
# which of them changed, and at the commit asks them all.
module TableFacts
  extend ActiveSupport::Concern

  class_methods do
    # The block runs at every commit with whether any of the columns changed
    # since the transaction began, on the record (so destroyed? and
    # previously_new_record? are to hand).
    def table_facts(*columns, &on_commit)
      columns = columns.flatten.map(&:to_s)
      after_save { table_facts_changed.concat(saved_changes.keys & columns) }
      after_rollback { table_facts_changed.clear }
      after_commit do
        changed = table_facts_changed.any?
        table_facts_changed.clear
        instance_exec(changed, &on_commit)
      end
    end
  end

  def table_facts_changed = (@table_facts_changed ||= [])
end

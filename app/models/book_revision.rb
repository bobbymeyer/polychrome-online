# frozen_string_literal: true

# One edit to a book entry, kept as the entry stood before it (Revisable). Putting it back is an edit like any other, so
# it is kept too, and can itself be taken back.
class BookRevision < ApplicationRecord
  belongs_to :world
  belongs_to :record, polymorphic: true
  belongs_to :user, optional: true

  scope :newest_first, -> { order(id: :desc) }

  # The entry as this revision has it, or the reasons it can't be (an entry it names has gone, say).
  def restore!
    attributes = snapshot.slice(*record.class.column_names).except(*Revisable::UNTRACKED)
    record.update(attributes) or raise Refusal, "#{record.name} can't go back to that: #{record.errors.full_messages.to_sentence}."
    record
  end

  # What the edit changed, in the entry's own columns: "level (was 3)", "ai_script".
  def changes_in_words
    changed_fields.map do |field|
      was = snapshot[field]
      label = field.humanize.downcase
      case was
      when nil then "#{label} (was nothing)"
      when String then "#{label} (was #{was.truncate(40).inspect})"
      when Numeric, true, false then "#{label} (was #{was})"
      else label # a list or a table of settings: said as the column's name
      end
    end
  end
end

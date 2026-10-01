# frozen_string_literal: true

# A secret as a chain of clues (docs/STORY.md, item 11): steps from a
# question to the truth, found one at a time wherever the party finds them,
# and a key story rows can ask about (how far the party has got). Written
# on a front's secrets in the setting and dealt in with them, or on a
# campaign's own.
class SecretsComeOutAClueAtATime < ActiveRecord::Migration[8.1]
  def change
    add_column :secrets, :steps, :text
    add_column :secrets, :found, :integer, default: 0, null: false
    add_column :secrets, :key, :string
    add_column :front_secrets, :steps, :text
    add_column :front_secrets, :key, :string
  end
end

# frozen_string_literal: true

# When someone last had the battle in front of them: its clock holds when
# nobody has, so a fight doesn't play itself out to the end unwatched.
class BattlesKnowWhoIsWatching < ActiveRecord::Migration[8.1]
  def change
    add_column :battles, :watched_at, :datetime
  end
end

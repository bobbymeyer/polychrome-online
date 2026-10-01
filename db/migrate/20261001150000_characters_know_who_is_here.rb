# frozen_string_literal: true

# When a character's player last had the table or the battle in front of
# them: the party panel says who is here.
class CharactersKnowWhoIsHere < ActiveRecord::Migration[8.1]
  def change
    add_column :characters, :seen_at, :datetime
  end
end

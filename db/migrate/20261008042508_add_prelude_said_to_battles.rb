# frozen_string_literal: true

# Whether a boss's entrance was said before the fight (a boss room's prelude, the GM's): the card in the fight
# then slams the name without saying the line again (battles/show).
class AddPreludeSaidToBattles < ActiveRecord::Migration[8.1]
  def change
    add_column :battles, :prelude_said, :boolean, default: false, null: false
  end
end

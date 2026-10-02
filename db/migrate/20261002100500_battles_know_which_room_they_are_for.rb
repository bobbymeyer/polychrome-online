# frozen_string_literal: true

# A room's fight was marked dealt with the moment the GM called it, so a
# boss fight lost (or fled) still counted the dungeon as cleared. The battle
# now remembers the room it is for, and the room is dealt with only when the
# battle is won (BattleRecord::Settlement).
#
# Renumbered from 20261002100000, which another migration already had: a
# database that ran it under the old number has the column already.
class BattlesKnowWhichRoomTheyAreFor < ActiveRecord::Migration[8.1]
  def change
    add_column :battles, :room, :string unless column_exists?(:battles, :room)
  end
end

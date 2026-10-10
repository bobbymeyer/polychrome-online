# frozen_string_literal: true

# A move that takes turns to go off can be broken by enough damage while it
# winds up (interrupt: a share of the user's max HP), and a move can give
# its user another go at once (again). Battle::State#validate_ability!.
class AddInterruptAndAgainToAbilities < ActiveRecord::Migration[8.1]
  def change
    add_column :abilities, :interrupt, :integer, default: 0, null: false
    add_column :abilities, :again, :boolean, default: false, null: false
  end
end

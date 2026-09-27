# frozen_string_literal: true

# Damage types replace elements (Battle::Types): every move's "element"
# becomes a "type", a monster's element affinities become exceptions to the
# type chart, and each monster gets a base type (normal unless the GM
# changes it). Battles already stored are rewritten the same way, so one in
# progress carries on. Old elements map to the nearest type.
class ElementsToTypes < ActiveRecord::Migration[8.1]
  TYPE_FOR = { "fire" => "fire", "ice" => "ice", "bolt" => "electric", "water" => "water", "wind" => "flying",
               "earth" => "ground", "holy" => "psychic", "dark" => "dark" }.freeze

  class Ability < ActiveRecord::Base; end
  class Item < ActiveRecord::Base; end
  class Monster < ActiveRecord::Base; end
  class Battle < ActiveRecord::Base; self.table_name = "battles"; end

  def up
    add_column :monsters, :base_type, :string, null: false, default: "normal"
    rename_column :monsters, :elements, :affinities
    [ Ability, Item, Monster, Battle ].each(&:reset_column_information)

    [ Ability, Item ].each do |model|
      model.find_each { |row| row.update_columns(effects: effects(row.effects)) }
    end
    Monster.find_each { |monster| monster.update_columns(affinities: affinities(monster.affinities)) }
    Battle.find_each do |battle|
      battle.update_columns(state: state(battle.state), initial_state: state(battle.initial_state))
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def effects(list)
    Array(list).map do |effect|
      next effect unless effect.is_a?(Hash) && effect.key?("element")

      effect.except("element").merge("type" => TYPE_FOR.fetch(effect["element"], "normal"))
    end
  end

  def affinities(hash)
    (hash || {}).to_h { |element, affinity| [ TYPE_FOR.fetch(element, element), affinity ] }
  end

  def state(state)
    return state unless state.is_a?(Hash)

    state = state.deep_dup
    state["abilities"]&.each_value { |ability| ability["effects"] = effects(ability["effects"]) }
    state["items"]&.each_value { |item| item["effects"] = effects(item["effects"]) }
    state["units"]&.each do |unit|
      unit["affinities"] = affinities(unit.delete("elements"))
      unit["types"] ||= []
    end
    state
  end
end

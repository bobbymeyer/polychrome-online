# frozen_string_literal: true

# Equipping from the party bag: one field per slot, holding an item id, or
# blank to take the slot off. All changes apply together or not at all.
class Characters::EquipmentController < ApplicationController
  include CampaignScoped

  before_action :set_character
  before_action :require_character_manager

  def update
    choices = params.expect(equipment: Character::SLOTS).to_h
    equipped = @character.equipped
    changes = choices.reject { |slot, item_id| equipped[slot]&.item_id.to_s == item_id.to_s }
    items = @world.items.where(id: changes.values.compact_blank).index_by { |item| item.id.to_s }

    misplaced = changes.select { |slot, id| id.present? && items[id]&.slot != slot }
    return sheet_error("#{misplaced.keys.to_sentence} can't hold that") if misplaced.any?

    Character.transaction do
      changes.each { |slot, id| id.blank? ? @character.unequip!(slot) : @character.equip!(items[id]) }
    end
    redirect_to character_path(@character), notice: "Equipment updated.", status: :see_other
  end
end

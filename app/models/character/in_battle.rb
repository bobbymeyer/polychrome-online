# frozen_string_literal: true

# A character as the battle engine sees them (Battle::State.build).
module Character::InBattle
  extend ActiveSupport::Concern

  class_methods do
    def from_battle_unit(unit_id)
      unit_id.to_s.delete_prefix("character_").to_i if unit_id.to_s.start_with?("character_")
    end
  end

  def battle_unit_id
    "character_#{id}"
  end

  # What the battle board draws: their determined face (or neutral), or
  # their job's art.
  def battle_art
    own = own_portrait_image("determined")
    BattleArt.new(image: own || job.image, variant: own ? {} : job.variant.to_h, colour: colour, level: level)
  end

  # Unit spec for Battle::State.build.
  def battle_spec
    {
      "id" => battle_unit_id,
      "name" => name,
      "stats" => stats,
      "hp" => current_hp,
      "mp" => current_mp,
      "abilities" => (battle_abilities.map(&:slug) + [ job.signature ].compact + worn_masks.map(&:don_slug)).uniq,
      "signature" => job.signature,
      "mastery" => battle_mastery.presence,
      "passives" => passives,
      "image" => { "book" => "jobs", "slug" => job.slug },
      "desperation" => job.desperation_ability&.slug,
      "level" => level,
      "technique" => job.technique,
      "coward" => (true if coward?)
    }.merge(job.battle_type).compact
  end

  # The masks they wear: each one's Don is on their menu (Item#don_ability).
  def worn_masks
    equipped_items.select(&:mask?)
  end
end

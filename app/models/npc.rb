# frozen_string_literal: true

# Someone the GM can speak as (§7, GM possession).
#
# An NPC can also fight: linked to a Bestiary entry, they're a recurring
# antagonist. They come into battle under their own name and face, as a
# boss. If they get away (the GM sends them off the field), they come back
# stronger next time; knocked out, they're finished. A villain from the
# setting's cast slips away the first time they're knocked out
# (BattleRecord::Settlement), and a dungeon they call home has them in its
# boss room (Location::Exploration).
class Npc < ApplicationRecord
  include Portrayed
  include Colourable

  # Stronger by this percent for every time they've got away.
  GROWTH = 15
  SCALED = %w[max_hp max_mp str mag vit spr agi atk def mdef].freeze

  include CampaignPages

  belongs_to :campaign
  belongs_to :location, optional: true
  belongs_to :monster, optional: true
  belongs_to :world_figure, optional: true
  has_many :messages, as: :speaker, dependent: :nullify

  validates :name, presence: true
  validate :monster_from_the_campaign_world

  scope :antagonists, -> { where.not(monster_id: nil) }
  scope :at_large, -> { antagonists.where(defeated_at: nil) }

  def antagonist?
    monster.present?
  end

  def defeated?
    defeated_at.present?
  end

  def battle_unit_id
    "npc_#{id}"
  end

  def self.from_battle_unit(unit_id)
    unit_id.to_s.delete_prefix("npc_").to_i if unit_id.to_s.start_with?("npc_")
  end

  def strength_percent
    100 + (GROWTH * escapes)
  end

  # Enemy spec for Battle::State.build: the Bestiary entry's, under this
  # NPC's name, as a boss, stronger for every escape.
  def battle_spec
    spec = monster.to_engine.except("count")
    stats = spec["stats"].to_h { |stat, value| [ stat, SCALED.include?(stat) ? value * strength_percent / 100 : value ] }
    spec.merge("id" => battle_unit_id, "name" => name, "stats" => stats, "boss" => true, "named" => true,
               "image" => { "book" => "npcs", "slug" => id.to_s })
  end

  # What the battle board draws: their angry face, or the monster's art.
  def battle_art
    own = own_portrait_image("angry")
    BattleArt.new(image: own || monster&.image, variant: own ? {} : monster&.variant.to_h, colour: colour, level: monster&.level)
  end

  private

  def monster_from_the_campaign_world
    errors.add(:monster, "must come from #{campaign.world.name}'s Bestiary") if monster && campaign && monster.world_id != campaign.world_id
  end
end

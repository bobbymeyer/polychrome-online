# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/base_world")

RSpec.describe Character do
  let(:world) { Seeds::BaseWorld.run }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road") }
  let(:job) { ->(slug) { world.jobs.find_by!(slug: slug) } }
  let(:item) { ->(slug) { world.items.find_by!(slug: slug) } }
  let(:ability) { ->(slug) { world.abilities.find_by!(slug: slug) } }

  def create(name: "Bartz", job_slug: "knight", level: 5, job_level: 1)
    campaign.characters.create!(name: name, job: job.(job_slug), starting_level: level, starting_job_level: job_level, starting_gear: false)
  end

  describe "creation" do
    it "starts at the chosen level and job level" do
      bartz = create(level: 7, job_level: 2)
      expect(bartz.level).to eq(7)
      expect(bartz.exp).to eq(Stats::Growth.exp_for_level(7))
      expect(bartz.character_job).to have_attributes(level: 2, abp: 30) # knight rows: 10 + 20
      expect(bartz.native_abilities.map(&:slug)).to eq(%w[war_cry armor_break])
    end

    it "starts about one job level per two levels when no job level is given" do
      lenna = campaign.characters.create!(name: "Lenna", job: job.("white_mage"), starting_level: 5)
      expect(lenna.character_job.level).to eq(3)
      expect(lenna.native_abilities.map(&:slug)).to eq(%w[cure silence esuna])
      expect(campaign.characters.create!(name: "Krile", job: job.("black_mage")).character_job.level).to eq(1) # level 1
    end

    it "arrives in the cheapest gear their job can use, but no accessory" do
      lenna = campaign.characters.create!(name: "Lenna", job: job.("white_mage"), starting_level: 5)
      expect(lenna.equipped.transform_values { |slot| slot.item.slug }).to eq("weapon" => "staff", "body" => "cotton_robe", "head" => "leather_cap")
      expect(lenna.stats["atk"]).to be_positive
      expect(campaign.inventories.sum(:quantity)).to eq(0) # issued, not taken from the bag
    end

    it "can start with nothing learned" do
      expect(create(job_level: 0).native_abilities).to be_empty
    end

    it "needs a job from the campaign's world" do
      alien = World.create!(slug: "elsewhere", name: "Elsewhere").jobs.create!(name: "Alien")
      character = campaign.characters.new(name: "X", job: alien)
      expect(character).not_to be_valid
      expect(character.errors[:job]).to include(/Base World/)
    end
  end

  describe "stats" do
    it "derives from level base, job, gear and innates, stage by stage" do
      bartz = create
      campaign.add_item!(item.("broadsword"))
      campaign.add_item!(item.("power_ring"))
      bartz.equip!(item.("broadsword"))
      bartz.equip!(item.("power_ring"))

      stages = bartz.reload.stat_stages
      base = Stats::Growth.base_stats(5)
      expect(stages[:base]).to eq(base)
      expect(stages[:job]["str"]).to eq(12 * 120 / 100)
      expect(stages[:equipment]).to include("str" => 14 + 5, "atk" => 14)
      expect(stages[:total]["def"]).to eq(stages[:equipment]["def"] * 110 / 100) # Knight innate: def +10%
      expect(bartz.stats).to eq(stages[:total])
    end

    it "keeps HP and MP between battles, clamped to the current maximum" do
      bartz = create
      expect(bartz.current_hp).to eq(bartz.stats["max_hp"])
      bartz.update!(hp: 9999, mp: 3)
      expect(bartz.current_hp).to eq(bartz.stats["max_hp"])
      expect(bartz.current_mp).to eq(3)
      bartz.update!(hp: 0)
      expect(bartz).not_to be_conscious
      campaign.rest!
      expect(bartz.reload.current_hp).to eq(bartz.stats["max_hp"])
    end
  end

  describe "#gain!" do
    it "levels up and learns abilities, and reports what changed" do
      bartz = create(job_level: 0)
      changes = bartz.gain!(exp: 1000, abp: 30)
      expect(changes).to eq("exp" => 1000, "abp" => 30, "level" => [ 5, 11 ], "learned" => [ "War Cry", "Armor Break" ], "to_next" => 120)
      expect(bartz.reload.level).to eq(11) # 200 + 1000 EXP
    end

    it "only feeds ABP to the current job" do
      bartz = create
      bartz.change_job!(job.("thief"))
      bartz.gain!(abp: 10)
      expect(bartz.character_job(job.("knight")).abp).to eq(10)
      expect(bartz.character_job(job.("thief")).abp).to eq(10)
    end
  end

  describe "jobs" do
    it "remembers progress in every job" do
      bartz = create(job_level: 2)
      bartz.change_job!(job.("black_mage"))
      expect(bartz.native_abilities).to be_empty
      expect(bartz.learned_abilities.map(&:slug)).to eq(%w[war_cry armor_break])
      bartz.change_job!(job.("knight"))
      expect(bartz.character_job.level).to eq(2)
    end

    it "sends gear the new job can't use back to the bag" do
      bartz = create
      campaign.add_item!(item.("broadsword"))
      campaign.add_item!(item.("power_ring"))
      bartz.equip!(item.("broadsword"))
      bartz.equip!(item.("power_ring"))
      bartz.change_job!(job.("black_mage"))
      expect(bartz.equipped.keys).to eq([ "accessory" ])
      expect(campaign.quantity_of(item.("broadsword"))).to eq(1)
    end

    it "clears ability slots the new job doesn't have" do
      bartz = create(job_level: 2)
      bartz.change_job!(job.("freelancer"))
      bartz.set_ability_slots!([ ability.("war_cry"), ability.("armor_break") ])
      bartz.change_job!(job.("thief"))
      expect(bartz.slotted_abilities.map(&:slug)).to eq(%w[war_cry])
    end
  end

  describe "equipment" do
    let(:bartz) { create }

    it "comes from the bag and goes back to it" do
      campaign.add_item!(item.("broadsword"))
      bartz.equip!(item.("broadsword"))
      expect(campaign.quantity_of(item.("broadsword"))).to eq(0)
      expect(bartz.equipped["weapon"].item.slug).to eq("broadsword")

      campaign.add_item!(item.("dagger")) # knights can't use knives
      expect { bartz.equip!(item.("dagger")) }.to raise_error(ActiveRecord::RecordInvalid, /can't equip Dagger/)

      bartz.unequip!("weapon")
      expect(campaign.quantity_of(item.("broadsword"))).to eq(1)
      expect(bartz.equipped).to be_empty
    end

    it "swaps, returning the old item" do
      campaign.add_item!(item.("broadsword"), 2)
      bartz.equip!(item.("broadsword"))
      bartz.equip!(item.("broadsword"))
      expect(campaign.quantity_of(item.("broadsword"))).to eq(1)
    end

    it "can't equip what isn't in the bag, and changes nothing if it fails" do
      expect { bartz.equip!(item.("broadsword")) }.to raise_error(ActiveRecord::RecordInvalid, /not in the bag/)
      expect(bartz.equipped).to be_empty
    end

    it "never takes a consumable" do
      campaign.add_item!(item.("potion"))
      expect { bartz.equip!(item.("potion")) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "ability slots" do
    it "hold learned abilities from other jobs, up to the job's slot count" do
      bartz = create(job_level: 2)
      bartz.change_job!(job.("thief"))
      bartz.set_ability_slots!([ ability.("armor_break") ])
      expect(bartz.battle_spec["abilities"]).to eq(%w[armor_break])

      expect { bartz.set_ability_slots!([ ability.("war_cry"), ability.("armor_break") ]) }
        .to raise_error(ActiveRecord::RecordInvalid, /1 ability slot/)
      expect { bartz.set_ability_slots!([ ability.("fire") ]) }
        .to raise_error(ActiveRecord::RecordInvalid, /Fire not learned/)
      expect(bartz.slotted_abilities.map(&:slug)).to eq(%w[armor_break])
    end
  end

  it "becomes a battle unit the engine accepts" do
    bartz = create
    bartz.update!(hp: 40)
    spec = bartz.battle_spec
    expect(spec).to include("id" => "character_#{bartz.id}", "hp" => 40, "abilities" => %w[war_cry],
                            "image" => { "book" => "jobs", "slug" => "knight" })
    expect(Character.from_battle_unit(spec["id"])).to eq(bartz.id)
    expect(Character.from_battle_unit("goblin_a")).to be_nil
    state = world.battle(seed: 1, party: [ spec ], monsters: { "goblin" => 1 })
    expect(state["units"].first).to include("hp" => 40, "stats" => bartz.stats)
  end
end

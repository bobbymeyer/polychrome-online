# frozen_string_literal: true

require "rails_helper"

RSpec.describe Character do
  let(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road") }
  let(:job) { ->(slug) { world.jobs.find_by!(slug: slug) } }
  let(:item) { ->(slug) { world.items.find_by!(slug: slug) } }
  let(:ability) { ->(slug) { world.abilities.find_by!(slug: slug) } }

  def create(name: "Bartz", job_slug: "knight", level: 5, job_level: 1)
    campaign.characters.create!(name: name, job: job.(job_slug), starting_level: level, starting_job_level: job_level, starting_gear: false)
  end

  describe "creation" do
    it "starts at the chosen level and job level" do
      bartz = create(level: 7, job_level: 12)
      expect(bartz.level).to eq(7)
      expect(bartz.exp).to eq(Stats::Growth.exp_for_level(7))
      expect(bartz.character_job).to have_attributes(level: 12, abp: 21) # 12 + 12²/16
      expect(bartz.native_abilities.map(&:slug)).to eq(%w[war_cry armor_break])
    end

    it "starts about two job levels per level when no job level is given" do
      lenna = campaign.characters.create!(name: "Lenna", job: job.("white_mage"), starting_level: 5)
      expect(lenna.character_job.level).to eq(10)
      expect(lenna.native_abilities.map(&:slug)).to eq(%w[cure silence barrier])
      expect(campaign.characters.create!(name: "Krile", job: job.("black_mage")).character_job.level).to eq(2) # level 1
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
      bartz.update!(hp: 20)
      campaign.sleep!
      expect(bartz.reload.current_hp).to eq(bartz.stats["max_hp"])
      bartz.update!(hp: 0)
      expect(bartz).not_to be_conscious
      campaign.sleep!
      expect(bartz.reload).not_to be_conscious # a night's rest raises nobody
    end
  end

  describe "#gain!" do
    it "levels up and learns abilities, and reports what changed" do
      bartz = create(job_level: 0)
      changes = bartz.gain!(exp: 1000, abp: 30)
      expect(changes).to include("exp" => 1000, "abp" => 30, "level" => [ 5, 11 ], "learned" => [ "War Cry", "Armor Break", "Double Cut" ], "to_next" => 120)
    expect(changes["abilities"].map { |a| a["name"] }).to eq([ "War Cry", "Armor Break", "Double Cut" ])
      expect(bartz.reload.level).to eq(11) # 200 + 1000 EXP
    end

    it "only feeds ABP to the current job" do
      bartz = create
      bartz.change_job!(job.("thief"))
      bartz.gain!(abp: 10)
      expect(bartz.character_job(job.("knight")).abp).to eq(1) # job level 1
      expect(bartz.character_job(job.("thief")).abp).to eq(10)
    end
  end

  describe "jobs" do
    it "remembers progress in every job" do
      bartz = create(job_level: 12)
      bartz.change_job!(job.("black_mage"))
      expect(bartz.native_abilities).to be_empty
      expect(bartz.learned_abilities.map(&:slug)).to eq(%w[war_cry armor_break])
      bartz.change_job!(job.("knight"))
      expect(bartz.character_job.level).to eq(12)
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
      bartz = create(job_level: 12)
      bartz.change_job!(job.("freelancer"))
      bartz.set_ability_slots!([ ability.("war_cry"), ability.("armor_break") ])
      bartz.change_job!(job.("thief"))
      expect(bartz.slotted_abilities.map(&:slug)).to eq(%w[war_cry])
    end
  end

  describe "mastery" do
    # One Cure on a wounded ally, same seed, same level: only the job and
    # mastery differ.
    def cure_heals(character)
      ally = { "id" => "ally", "name" => "Ally", "hp" => 1, "stats" => character.stats.merge("max_hp" => 5000, "agi" => 0) }
      state = world.battle(seed: 5, party: [ character.battle_spec, ally ], monsters: { "goblin" => 1 })
      state["units"].find { |u| u["id"] == "ally" }["abilities"] = []
      state, = Battle::Resolver.apply(state, { type: "command", actor: character.battle_unit_id,
                                               command: { kind: "ability", ability: "cure", target: "ally" } })
      _, events = Battle::Resolver.apply(state, { type: "command", actor: "ally", command: { kind: "defend" } })
      events.find { |e| e["type"] == "heal" && e["target"] == "ally" }.fetch("amount")
    end

    it "grows each ability with the job level, and gives the active job a bonus" do
      rosa = create(job_slug: "white_mage", level: 30, job_level: 1)
      expect(rosa.battle_spec["mastery"]).to include("cure" => { "power" => 125 })
      rosa.gain!(abp: Stats::Growth.abp_for_job_level(21) - rosa.character_job.abp)
      expect(rosa.reload.battle_spec["mastery"]["cure"]).to eq("power" => 150) # halfway: +25, and +25 in the job
    end

    it "keeps a master White Mage who turned Knight a better healer than a new White Mage" do
      beginner = create(name: "Rosa", job_slug: "white_mage", level: 30, job_level: 1)
      master = create(name: "Porom", job_slug: "white_mage", level: 30, job_level: 100)
      master.change_job!(job.("knight"))
      master.set_ability_slots!([ ability.("cure") ])
      entry = master.reload.battle_spec["mastery"]["cure"]
      expect(entry["power"]).to eq(150)
      expect(entry["stats"]["mag"]).to be > master.stats["mag"] # a White Mage's MAG, not a Knight's
      expect(cure_heals(master)).to be > cure_heals(beginner)
    end

    it "reports abilities as they're mastered, and the job at level 100" do
      bartz = create(job_level: 40)
      changes = bartz.gain!(abp: Stats::Growth.abp_for_job_level(41) - bartz.character_job.abp)
      expect(changes).to include("mastered_abilities" => [ "War Cry" ], "job_level" => [ 40, 41 ])
      expect(changes["next_lesson"]).to eq("name" => "Oathblade", "job_level" => 50,
                                           "abp" => Stats::Growth.abp_for_job_level(50) - bartz.character_job.abp)
      changes = bartz.gain!(abp: 10_000)
      expect(changes["mastered_abilities"]).to eq([ "Armor Break", "Double Cut", "Shield Bash", "Stalwart", "Oathblade" ])
      expect(changes["learned"]).to eq([ "Oathblade" ]) # the capstone, at job level 50, long before the job's mastered
      expect(changes).not_to have_key("next_lesson")
      expect(changes["mastered"]).to eq("job" => "Knight", "passive" => "second_wind")
    end

    it "brings the job's type into battle, and its Attack strikes with it" do
      spec = create.battle_spec
      expect(spec).to include("types" => %w[steel], "attack_type" => "steel", "immune_as_resist" => true, "signature" => "cover")
      expect(create(name: "Butz", job_slug: "freelancer").battle_spec).not_to have_key("attack_type")
    end

    it "gives a caster a plain Attack, so it's never useless against what its type can't touch" do
      spec = create(name: "Krile", job_slug: "summoner").battle_spec
      expect(spec).to include("types" => %w[ghost])
      expect(spec).not_to have_key("attack_type")
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
      bartz = create(job_level: 12)
      bartz.change_job!(job.("thief"))
      bartz.set_ability_slots!([ ability.("armor_break") ])
      expect(bartz.battle_spec["abilities"]).to eq(%w[armor_break mug]) # and the Thief's own command

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
    expect(spec).to include("id" => "character_#{bartz.id}", "hp" => 40, "abilities" => %w[war_cry cover], "passives" => %w[second_wind], "level" => 5,
                            "image" => { "book" => "jobs", "slug" => "knight" })
    expect(Character.from_battle_unit(spec["id"])).to eq(bartz.id)
    expect(Character.from_battle_unit("goblin_a")).to be_nil
    state = world.battle(seed: 1, party: [ spec ], monsters: { "goblin" => 1 })
    expect(state["units"].first).to include("hp" => 40, "stats" => bartz.stats)
  end

  it "brings their job's desperation move into battle, and says why they're here" do
    bartz = create
    bartz.update!(motive: "  “I owe the Crystal a life.”  ")
    expect(bartz.motive).to eq("I owe the Crystal a life.")
    expect(bartz.battle_spec).to include("desperation" => "unbroken_line")
    state = world.battle(seed: 1, party: [ bartz.battle_spec ], monsters: { "goblin" => 1 })
    expect(state["units"].first["desperation"]).to eq("unbroken_line")

    job.("knight").update!(desperation: nil)
    expect(bartz.reload.battle_spec).not_to have_key("desperation")
    expect(bartz.update(motive: "x" * 141)).to be(false)
  end

  it "carries its job's signature and passive, and keeps a mastered job's passive in every job" do
    bartz = create(job_slug: "knight")
    expect(bartz.battle_spec).to include("passives" => %w[second_wind])
    expect(bartz.battle_spec["abilities"]).to include("cover")

    changes = bartz.gain!(abp: 10_000)
    expect(changes["mastered"]).to eq("job" => "Knight", "passive" => "second_wind")
    bartz.change_job!(job.("thief"))
    expect(bartz.reload.passives).to eq(%w[first_strike second_wind])
    expect(bartz.battle_spec["abilities"]).to include("mug")
    expect(bartz.battle_spec["abilities"]).not_to include("cover")
  end
end

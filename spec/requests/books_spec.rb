# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Books", type: :request do
  let(:world) { create_world }

  describe "worlds" do
    it "lists worlds and shows a world's shelf of books" do
      create_monster(world)
      get root_path
      expect(response.body).to include("Testland")

      get world_path(world)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Bestiary", "Archetype Compendium", "Grimoire", "Armory", "Goblin")
    end

    it "creates and edits a world, keeping its slug" do
      post worlds_path, params: { world: { name: "Second World", slug: "second" } }
      expect(response).to redirect_to(world_path("second"))

      patch world_path("second"), params: { world: { name: "Renamed", slug: "hacked" } }
      expect(World.find_by!(slug: "second").name).to eq("Renamed")
    end

    it "starts a world from another world's books, copies and all" do
      base = base_world
      base.monsters.find_by!(slug: "goblin").image.attach(io: StringIO.new("png"), filename: "goblin.png", content_type: "image/png")
      post worlds_path, params: { world: { name: "Ashfall", slug: "ashfall" }, copy_from: "base" }
      ashfall = World.find_by!(slug: "ashfall")
      World::BOOKS.each { |book| expect(ashfall.public_send(book).count).to eq(base.public_send(book).count), book.to_s }

      knight = ashfall.jobs.find_by!(slug: "knight")
      expect(knight.job_levels.map(&:ability)).to all(have_attributes(world_id: ashfall.id))
      cave = ashfall.location_templates.find_by!(slug: "goblin_cave")
      expect(cave.encounter_table.world).to eq(ashfall)
      expect(ashfall.monsters.find_by!(slug: "goblin").image).to be_attached

      ashfall.monsters.find_by!(slug: "goblin").update!(name: "Ash Goblin")
      expect(base.monsters.find_by!(slug: "goblin").name).to eq("Goblin")
    end

    it "leaves no half-made world when a copy fails, and says what couldn't be copied" do
      base = base_world
      base.monsters.find_by!(slug: "goblin").update_column(:phases, [ { "hp_below" => 50, "becomes" => "nobody" } ]) # broken behind validation's back
      post worlds_path, params: { world: { name: "Cinders", slug: "cinders" }, copy_from: "base" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Base World&#39;s monster Goblin couldn&#39;t be copied", "nobody, which is not in the Bestiary")
      expect(World.find_by(slug: "cinders")).to be_nil
    end

    it "copies only the rules when asked: the books without the setting" do
      base = base_world
      post worlds_path, params: { world: { name: "Velvet", slug: "velvet" }, copy_from: "base", rules_only: "1" }
      velvet = World.find_by!(slug: "velvet")
      expect(flash[:notice]).to end_with("rules.")
      World::BOOKS.each { |book| expect(velvet.public_send(book).count).to eq(base.public_send(book).count), book.to_s }
      expect(velvet.skills).to eq(base.skills)
      expect([ velvet.world_places, velvet.world_figures, velvet.codex_entries, velvet.world_fronts ].map(&:count)).to eq([ 0, 0, 0, 0 ])
      expect([ velvet.voice, velvet.terms, velvet.calendar, velvet.history ]).to all(be_blank)
      expect(velvet.date(12)).to eq("Day 12")
    end

    it "re-renders the form with errors" do
      post worlds_path, params: { world: { name: "", slug: "9 lives" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("problems to fix", "must be lowercase letters, digits and underscores, starting with a letter")
    end

    it "takes hyphens and capitals in an address as underscores" do
      post worlds_path, params: { world: { name: "Persona Scratch", slug: "Persona-Scratch" } }
      expect(response).to redirect_to(world_path("persona_scratch"))
    end
  end

  it "shows the type chart, and each monster's type and what that makes it weak to" do
    get world_types_path(world)
    expect(response.body).to include("Types")
    expect(page.css("span").map(&:text)).to include("Ghost")
    expect(page.at(".is-zero")).to be_present
    expect(response.body).not_to include("Fairy", "Dragon")

    monster = create_monster(world, slug: "skeleton", base_type: "dark", affinities: { fire: "weak" })
    get world_bestiary_monster_path(world, monster)
    expect(page.css("span").map(&:text)).to include("Dark", "Fighting", "Bug")
    expect(response.body).to include("Weak to", "Breaks the chart: weak fire")
    get world_bestiary_monsters_path(world)
    expect(response.body).to include("Type chart", "Fighting, Bug, Fire").or include("Fire, Fighting, Bug")
  end

  it "explains the game's words where they're used, and all together on How to play" do
    get how_to_play_path
    expect(page.text).to include("How to play", "Ability points", "(D&D: Dex)")
    expect(page.at(".gloss")).to be_present

    monster = create_monster(world)
    get world_bestiary_monster_path(world, monster)
    expect(page.css("[data-gloss]").map { |n| n["data-gloss"] }).to include(start_with("Agility. Who acts first"))
  end

  describe "Grimoire" do
    let(:form) do
      { name: "Bio", kind: "magic", target: "single_enemy", mp_cost: "6", gesture: "tint", description: "Rot.",
        effects: { "0" => { primitive: "elemental", type: "dark", power: "12", hits: "", chance: "" },
                   "1" => { primitive: "status", kind: "poison", chance: "100", duration: "4" },
                   "2" => { primitive: "", power: "" } } }
    end

    it "runs the full CRUD cycle" do
      get new_world_grimoire_ability_path(world)
      expect(response).to have_http_status(:ok)
      # A Status effect offers the statuses it can give; those with a primitive of their own (charging, shield) come from it.
      statuses = page.css("select[aria-label='Status 1'] option").map { |o| o["value"] }
      expect(statuses).to include("poison", "doom", "haste")
      expect(statuses).not_to include("charging", "shield", "down")
      expect(page.at("[data-controller=rows] button[data-action='rows#add']").text).to eq("Add a row") # more than the two blanks

      post world_grimoire_abilities_path(world), params: { ability: form }
      ability = world.abilities.find_by!(slug: "bio")
      expect(response).to redirect_to(world_grimoire_ability_path(world, "bio"))
      expect(ability.effects.size).to eq(2)

      get world_grimoire_abilities_path(world)
      expect(response.body).to include("Bio", "Dark damage, power 12")

      get world_grimoire_ability_path(world, "bio")
      expect(response.body).to include("Rot.", "Poison (100%, 4 turns)", "6 MP")

      get edit_world_grimoire_ability_path(world, "bio")
      expect(response).to have_http_status(:ok)

      patch world_grimoire_ability_path(world, "bio"), params: { ability: form.merge(mp_cost: "8", slug: "renamed") }
      expect(ability.reload.mp_cost).to eq(8)
      expect(ability.slug).to eq("bio")

      delete world_grimoire_ability_path(world, "bio")
      expect(response).to redirect_to(world_grimoire_abilities_path(world))
      expect(world.abilities.count).to eq(0)
    end

    it "shows engine validation errors on the form" do
      post world_grimoire_abilities_path(world), params: { ability: form.merge(effects: { "0" => { primitive: "heal" } }) }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("heal needs power")
    end

    it "refuses to delete an ability a job still teaches" do
      ability = create_ability(world)
      create_job(world).job_levels.create!(level: 1, ability: ability)
      delete world_grimoire_ability_path(world, ability)
      expect(response).to redirect_to(world_grimoire_ability_path(world, ability))
      expect(Ability.exists?(ability.id)).to be(true)
    end

    it "cross-references jobs and monsters" do
      ability = create_ability(world)
      create_job(world, name: "Black Mage").job_levels.create!(level: 1, ability: ability)
      create_monster(world, name: "Imp", ai_script: [ { use: "fire" } ])
      get world_grimoire_ability_path(world, ability)
      expect(response.body).to include("Taught by", "Black Mage", "archetype level 1", "Used by", "Imp")
    end
  end

  describe "Bestiary" do
    before do
      create_ability(world)
      create_item(world, slug: "potion", category: "consumable", stats: {}, target: "single_ally",
                         effects: [ { primitive: "heal", power: 30 } ])
    end

    it "writes a boss's phases and a rule's once and line on the form, and reads them back on the page" do
      king = create_monster(world, slug: "goblin_king", name: "Goblin King", boss: true)
      goblin = create_monster(world)
      get edit_world_bestiary_monster_path(world, goblin)
      expect(response.body).to include("Phases", "Once", "Says", "Becomes", "When hit", "As it falls", "Any blow")
      patch world_bestiary_monster_path(world, goblin),
            params: { monster: { ai_script: { "0" => { use: "fire", once: "1", say: "Burn.", chance: "50" }, "1" => { use: "attack", once: "0" },
                                              "2" => { when: "hit", by: "fire", use: "fire" } },
                                 phases: { "0" => { hp_below: "50", becomes: "goblin_king", say: "Now you see.", restore: "10" } } } }
      expect(response).to redirect_to(world_bestiary_monster_path(world, goblin))
      expect(goblin.reload.phases).to eq([ { "hp_below" => 50, "becomes" => "goblin_king", "say" => "Now you see.", "restore" => 10 } ])
      expect(goblin.ai_script.first).to include("once" => true, "say" => "Burn.")
      get world_bestiary_monster_path(world, goblin)
      expect(response.body).to include("(once)", "“Burn.”", "Below 50% HP: becomes", "Goblin King", "10% HP back", "“Now you see.”", "When hit by Fire:")
      get world_bestiary_monster_path(world, king)
      expect(response.body).to include("A form of")
    end

    it "keeps a boss's own music when its track is given a scene, says whose it is in the Music book, and lets it go when the track does" do
      theme = world.tracks.create!(name: "Forge theme", source: "link", url: "https://youtu.be/dQw4w9WgXcQ")
      warden = create_monster(world, slug: "warden", name: "Warden", boss: true, music: "track:#{theme.id}")
      theme.update!(scene: "boss") # now a kind of scene's track: not in the "called by name" list
      get edit_world_bestiary_monster_path(world, warden)
      expect(page.at("select[name='monster[music]'] option[selected]")&.text).to eq("♪ Forge theme (the boss track now)")
      patch world_bestiary_monster_path(world, warden), params: { monster: { name: "Warden", music: "track:#{theme.id}" } } # saved as it came
      expect(warden.reload.music).to eq("track:#{theme.id}")

      get world_tracks_path(world)
      expect(page.text.squish).to include("Its own music for Warden")
      theme.destroy!
      expect(warden.reload.music).to be_nil # back to the boss track, not pointing at nothing
    end

    it "takes a chosen plate colour, or picks one from the name" do
      goblin = create_monster(world)
      get world_bestiary_monster_path(world, goblin)
      expect(response.body).to include(ApplicationController.helpers.plate_style("goblin"))

      patch world_bestiary_monster_path(world, goblin), params: { monster: { colour: "pink" } }
      expect(goblin.reload.colour).to eq("pink")
      get world_bestiary_monster_path(world, goblin)
      expect(response.body).to include("--plate: #F6BCD0;")

      patch world_bestiary_monster_path(world, goblin), params: { monster: { colour: "mauve" } }
      expect(response).to have_http_status(:unprocessable_content)
      patch world_bestiary_monster_path(world, goblin), params: { monster: { colour: "" } }
      expect(goblin.reload.colour).to be_nil
    end

    let(:form) do
      {
        name: "Goblin", level: "2", exp: "6", gil: "12", abp: "1",
        stats: monster_stats.transform_values(&:to_s),
        elements: { fire: "weak", ice: "normal" }, status_immune: [ "", "sleep" ],
        ai_script: { "0" => { chance: "25", ally_ko: "0", use: "fire", target: "" },
                     "1" => { ally_ko: "0", use: "attack", target: "lowest_hp" },
                     "2" => { ally_ko: "0", use: "" } },
        drops: { "0" => { item: "potion", chance: "30" }, "1" => { item: "", chance: "" } },
        variant: { hue: "40", scale: "", flip: "1" },
        image: Rack::Test::UploadedFile.new(file_fixture("goblin.png"), "image/png")
      }
    end

    it "creates a monster from the form, image and all, and renders its page" do
      post world_bestiary_monsters_path(world), params: { monster: form }
      monster = world.monsters.find_by!(slug: "goblin")
      expect(monster.ai_script).to eq([ { "if" => { "chance" => 25 }, "use" => "fire" },
                                       { "use" => "attack", "target" => "lowest_hp" } ])
      expect(monster.status_immune).to eq([ "sleep" ])
      expect(monster.variant).to eq("hue" => 40, "flip" => true)
      expect(monster.image).to be_attached

      follow_redirect!
      expect(response.body).to include("25% of the time", "Fire", "Lowest hp", "Potion", "(30%)", "Immune to")
      expect(response.body).to include("hue-rotate(40deg)", "scaleX(-1)")
    end

    it "shows the stat block errors" do
      post world_bestiary_monsters_path(world), params: { monster: form.merge(stats: { max_hp: "10" }) }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("is missing")
    end

    it "orders the index by level" do
      create_monster(world, slug: "dragon", level: 9)
      create_monster(world, slug: "rat", level: 1)
      get world_bestiary_monsters_path(world)
      expect(response.body.index("Rat")).to be < response.body.index("Dragon")
    end
  end

  describe "Archetype Compendium" do
    it "edits the learn table through nested rows" do
      cure = create_ability(world, slug: "cure", target: "single_ally", effects: [ { primitive: "heal", power: 10 } ])
      raise_spell = create_ability(world, slug: "raise", target: "single_ally", effects: [ { primitive: "revive" } ])
      post world_compendium_jobs_path(world), params: { job: {
        name: "White Mage", stat_multipliers: { mag: "120", str: "" }, equip_categories: [ "", "staff", "robe" ],
        innates: { "0" => { stat: "mdef", add: "", percent: "20" }, "1" => { stat: "", add: "", percent: "" } },
        job_levels_attributes: { "0" => { level: "1", ability_id: cure.id },
                                 "1" => { level: "", ability_id: "" } }
      } }
      job = world.jobs.find_by!(slug: "white_mage")
      expect(job.equip_categories).to eq(%w[staff robe])
      expect(job.innates).to eq([ { "stat" => "mdef", "percent" => 20 } ])

      level = job.job_levels.sole
      patch world_compendium_job_path(world, job), params: { job: {
        name: "White Mage",
        job_levels_attributes: { "0" => { id: level.id, level: "1", ability_id: cure.id, _destroy: "1" },
                                 "1" => { level: "2", ability_id: raise_spell.id } }
      } }
      expect(job.reload.job_levels.map { |l| l.ability.slug }).to eq([ "raise" ])

      get world_compendium_job_path(world, job)
      expect(response.body).to include("Learn table", "Raise", "×1.20", "Staff")
    end
  end

  describe "Armory" do
    it "creates equipment and shows who can use it" do
      create_job(world, name: "Knight")
      post world_armory_items_path(world), params: { item: {
        name: "Broadsword", category: "sword", price: "200", target: "",
        stats: { atk: "14", def: "" }, effects: { "0" => { primitive: "" } }
      } }
      expect(response).to redirect_to(world_armory_item_path(world, "broadsword"))
      follow_redirect!
      expect(response.body).to include("Atk", "+14", "Equippable by", "Knight")
    end
  end

  describe "world isolation" do
    it "never serves one world's entries under another" do
      other = create_world(slug: "other", name: "Other")
      create_monster(other, slug: "wyrm")
      get world_bestiary_monster_path(world, "wyrm")
      expect(response).to have_http_status(:not_found)
    end

    it "404s for an unknown world" do
      get world_bestiary_monsters_path("nowhere")
      expect(response).to have_http_status(:not_found)
    end
  end
end

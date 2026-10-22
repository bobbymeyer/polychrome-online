# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Finding your way around a world's books", type: :request do
  let(:world) { create_world }

  def table(slug, entries)
    world.encounter_tables.create!(slug: slug, name: slug.humanize, terrain: "cave", tier: 1, entries: entries)
  end

  describe "the world's page" do
    it "groups what a world is made of by what you are doing, above the shelf of books" do
      get world_path(world)
      expect(page.css(".world-nav h2").map(&:text)).to eq([ "The rules", "The setting", "Taking it elsewhere" ])
      expect(page.css(".world-nav a").map(&:text)).to include("Types", "Codex", "Copy this world")
      expect(page.css(".shelf__book h2").map(&:text)).to eq(World::Books::LIST.map(&:title))
      expect(page.at("form.search-form input[name=q]")).to be_present
    end

    it "lists what the books leave loose, with a way to add what is missing" do
      create_monster(world, slug: "goblin")
      create_monster(world, slug: "ogre", name: "Ogre")
      create_monster(world, slug: "king", name: "King", boss: true)
      create_job(world) # teaches nothing
      table("road", [ { weight: 1, monsters: { "ogre" => 1 } } ])
      get world_path(world)

      loose = page.at(".loose-ends").text.squish
      expect(loose).to include("The Grimoire has no entries yet.", "The Armory has no entries yet.", "Archetypes that teach nothing: Knight",
                               "Monsters no encounter table sends against the party: Goblin")
      expect(loose).not_to include("The Bestiary has no entries", "Ogre,", "King") # met on a road; placed by hand
      expect(page.at(".loose-ends a[href='#{new_world_grimoire_ability_path(world)}']").text).to eq("Add one")
    end

    it "does not call a monster loose when a road sends it, another entry becomes it, or an ability calls it" do
      create_monster(world, slug: "goblin_king", name: "Goblin King")
      create_monster(world, slug: "goblin", phases: [ { hp_below: 50, becomes: "goblin_king" } ])
      create_monster(world, slug: "imp", name: "Imp")
      create_ability(world, slug: "call_imp", effects: [ { primitive: "summon", creature: "imp" } ])
      table("road", [ { weight: 1, monsters: { "goblin" => 1 } } ])
      get world_path(world)
      expect(page.at(".loose-ends").text).not_to include("no encounter table")
    end
  end

  describe "search" do
    before do
      create_monster(world, slug: "goblin")
      create_monster(world, slug: "goblin_king", name: "Goblin King")
      create_item(world, slug: "goblin_mask", name: "Goblin Mask", category: "mask")
      create_ability(world, slug: "fire", name: "50% Fire")
    end

    it "finds entries in every book by name or slug, grouped by book" do
      get world_search_path(world, q: "gob")
      expect(page.css("section.window h2").map(&:text)).to eq([ "Bestiary", "Armory" ])
      expect(page.css("section.window li a").map(&:text)).to eq([ "Goblin", "Goblin King", "Goblin Mask" ])
      get world_search_path(world, q: "GOBLIN_K")
      expect(response).to redirect_to(world_bestiary_monster_path(world, "goblin_king"))
    end

    it "takes a percent sign for what it is, and says when nothing is called that" do
      get world_search_path(world, q: "50%")
      expect(response).to redirect_to(world_grimoire_ability_path(world, "fire"))
      get world_search_path(world, q: "%")
      expect(response).to redirect_to(world_grimoire_ability_path(world, "fire")) # only one name has one
      get world_search_path(world, q: "dragon")
      expect(page.at(".empty").text).to include("Nothing in Testland's books is called “dragon”")
      get world_search_path(world)
      expect(page.at(".hint").text).to include("By name or slug")
    end

    it "sits in the masthead on every book page" do
      get world_bestiary_monsters_path(world)
      expect(page.at("header.topbar form.topbar__search input[name=q]")).to be_present
      expect(page.css("header.topbar .topbar__book").map(&:text)).to eq(World::Books::LIST.map(&:nav))
    end
  end
end

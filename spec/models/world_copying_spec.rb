# frozen_string_literal: true

require "rails_helper"

# A world's books name each other both ways: a summon calls a creature, a
# script uses a summon, a phase becomes an entry written after it. Copying
# has to take them all, in whatever order they were written.
RSpec.describe World::Copying do
  let(:source) { create_world(slug: "source", name: "Source") }

  before do
    create_monster(source, slug: "sprite", name: "Sprite")
    create_ability(source, slug: "call_sprite", target: "self", effects: [ { primitive: "summon", creature: "sprite", duration: 2 } ])
    create_monster(source, slug: "warden", name: "Warden", boss: true, ai_script: [ { once: true, use: "call_sprite" }, { use: "attack" } ],
                          phases: []) # the form comes after: set below
    create_monster(source, slug: "warden_cracked", name: "Warden, Cracked", boss: true)
    source.monsters.find_by!(slug: "warden").update!(phases: [ { hp_below: 50, becomes: "warden_cracked", say: "Now." } ])
  end

  it "copies a script that uses a summon and a phase that becomes a later entry, whole" do
    copy = World.create!(slug: "copy", name: "Copy")
    copy.copy_books_from!(source)
    World::BOOKS.each { |book| expect(copy.public_send(book).count).to eq(source.public_send(book).count), book.to_s }
    warden = copy.monsters.find_by!(slug: "warden")
    expect(warden.ai_script.first).to include("use" => "call_sprite", "once" => true)
    expect(warden.phases).to eq([ { "hp_below" => 50, "becomes" => "warden_cracked", "say" => "Now.", "restore" => 0 } ])
    expect(warden.forms.map(&:world)).to eq([ copy ])
    expect(copy.abilities.find_by!(slug: "call_sprite").effects.first).to include("creature" => "sprite")
  end

  it "copies the base world, phases, summons and all" do
    copy = World.create!(slug: "ashes", name: "Ashes")
    copy.copy_books_from!(base_world)
    expect(copy.monsters.find_by!(slug: "crystal_wyrm").phases.first).to include("becomes" => "crystal_wyrm_unbound")
    expect(copy.monsters.find_by!(slug: "crystal_wyrm_unbound").form_of.map(&:slug)).to eq([ "crystal_wyrm" ])
  end
end

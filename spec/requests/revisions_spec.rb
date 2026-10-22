# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Taking an edit to the books back", type: :request do
  let(:world) { create_world }
  let!(:goblin) { create_monster(world, level: 3) }

  it "keeps what an entry was before each edit, who made it, and which columns changed" do
    patch world_bestiary_monster_path(world, goblin), params: { monster: { name: "Goblin", level: "4", boss_line: "Hm." } }
    revision = goblin.reload.revisions.sole
    expect(revision).to have_attributes(user: @admin, world_id: world.id, changed_fields: %w[level boss_line])
    expect(revision.snapshot).to include("level" => 3, "name" => "Goblin")
    expect(revision.snapshot.keys).not_to include("slug", "id", "created_at", "updated_at")
    expect(revision.changes_in_words).to eq([ "level (was 3)", "boss line (was nothing)" ])

    patch world_bestiary_monster_path(world, goblin), params: { monster: { name: "Goblin", level: "4" } } # nothing changed
    expect(goblin.reload.revisions.count).to eq(1)
  end

  it "keeps the last few edits of an entry, and none once the entry is gone" do
    (Revisable::KEPT + 5).times { |n| goblin.update!(level: n + 10) }
    expect(goblin.revisions.count).to eq(Revisable::KEPT)
    expect(goblin.revisions.first.snapshot["level"]).to eq(Revisable::KEPT + 4 + 9) # the newest is the one before the last edit
    goblin.destroy!
    expect(BookRevision.count).to eq(0)
  end

  it "shows an entry's history and the world's recent edits, with the way to put it back" do
    goblin.update!(level: 4)
    create_monster(world, slug: "ogre", name: "Ogre").update!(level: 9)

    get world_revisions_path(world, book: "bestiary", slug: "goblin")
    expect(page.css("tbody tr").size).to eq(1)
    expect(page.text.squish).to include("History of Goblin", "level (was 3)")
    expect(page.at("form[action='#{world_revision_restore_path(world, goblin.revisions.first)}'] button, form[action='#{world_revision_restore_path(world, goblin.revisions.first)}'] input[type=submit]")).to be_present

    get world_revisions_path(world)
    expect(page.css("tbody tr td:nth-child(3)").map(&:text)).to contain_exactly("Goblin", "Ogre")
    get world_bestiary_monster_path(world, goblin)
    expect(page.at("a[href*='/revisions']").text).to eq("History (1)")
  end

  it "puts an entry back as it was, as an edit that can itself be taken back" do
    goblin.update!(level: 4, boss_line: "Hm.")
    before = goblin.revisions.first
    post world_revision_restore_path(world, before)
    expect(response).to redirect_to(world_bestiary_monster_path(world, goblin))
    expect(goblin.reload).to have_attributes(level: 3, boss_line: nil)
    expect(goblin.revisions.count).to eq(2)
    post world_revision_restore_path(world, goblin.revisions.first)
    expect(goblin.reload.level).to eq(4)
  end

  it "refuses to put an entry back where it no longer fits the books, and says why" do
    king = create_monster(world, slug: "king", name: "King")
    goblin.update!(phases: [ { hp_below: 50, becomes: "king" } ])
    goblin.update!(level: 5)
    withphase = goblin.revisions.first # as it was before the second edit: the phase written
    expect(withphase.snapshot["phases"]).to be_present
    goblin.update!(phases: [])
    king.destroy!

    post world_revision_restore_path(world, withphase), headers: { "Referer" => world_revisions_path(world) }
    expect(response).to redirect_to(world_revisions_path(world))
    expect(flash[:alert]).to include("Goblin can't go back to that", "king, which is not in the Bestiary")
    expect(goblin.reload).to have_attributes(level: 5, phases: [])
  end

  it "is for those who can change the world's books" do
    sign_out
    sign_in_as(make_user("Reader"))
    get world_revisions_path(world)
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to include("Only an admin can change Testland")
    post world_revision_restore_path(world, BookRevision.create!(world: world, record: goblin, snapshot: {}, changed_fields: []))
    expect(goblin.reload.level).to eq(3)
  end

  it "says before an entry is changed that campaigns play in the world" do
    get edit_world_bestiary_monster_path(world, goblin)
    expect(page.at(".live-warning")).to be_nil

    create_campaign(world: world, name: "The Crystal Road")
    get edit_world_bestiary_monster_path(world, goblin)
    expect(page.at(".live-warning").text.squish).to include("1 campaign play in Testland: The Crystal Road", "kept in the edit log")
    expect(page.at("[data-controller=draft][data-draft-key-value='edit:testland:bestiary:goblin'] form.book-form")).to be_present
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Deleting a world", type: :request do
  let(:lenna) { make_user("Lenna") }
  let!(:scratch) { World.create!(name: "Persona Scratch", slug: "persona_scratch", owner: lenna).tap { |w| w.copy_books_from!(base_world, rules_only: true) } }

  it "lets its maker delete a world nobody plays in, books and all" do
    sign_in_as(lenna)
    get edit_world_path(scratch)
    expect(response.body).to include("Delete Persona Scratch")

    expect { delete world_path(scratch) }.to change(World, :count).by(-1).and change(Monster, :count).by(-scratch.monsters.count)
    expect(response).to redirect_to(worlds_path)
  end

  it "keeps a world someone is playing in, and the root world, and doesn't let another GM delete it" do
    faris = make_user("Faris")
    scratch.campaigns.create!(name: "Faris's Run", gm: faris)
    sign_in_as(faris)
    get edit_world_path(scratch)
    expect(response.body).not_to include("Delete Persona Scratch")
    delete world_path(scratch)
    expect(World.exists?(scratch.id)).to be(true)

    sign_in_as(lenna)
    delete world_path(scratch)
    expect(flash[:alert]).to eq("A campaign is played in Persona Scratch (Faris's Run). Those go first.")
    expect(World.exists?(scratch.id)).to be(true)

    sign_in_as(@admin)
    delete world_path(base_world)
    expect(flash[:alert]).to include("Base World stays")
  end

  # The privilege belongs to the first world, not to a particular slug: it
  # was the Base World's and is Oda's now, and the check is World#root?.
  it "keeps whichever world is the first one, whatever it is called" do
    root = base_world # built before the suite's examples, so it is the first row
    expect(World.root).to eq(root)
    expect(root).to be_root
    expect(scratch).not_to be_root

    root.update!(name: "Oda", slug: "oda") # the seat doesn't move with the name
    sign_in_as(@admin)
    delete world_path(root)
    expect(flash[:alert]).to include("Oda stays")
    expect(World.exists?(root.id)).to be(true)
  end
end

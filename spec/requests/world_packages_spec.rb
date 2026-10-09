# frozen_string_literal: true

require "rails_helper"

RSpec.describe "World packages", type: :request do
  let!(:world) { base_world }

  def upload(zip)
    path = Rails.root.join("tmp", "world-#{SecureRandom.hex(4)}.zip")
    File.binwrite(path, zip)
    Rack::Test::UploadedFile.new(path, "application/zip")
  end

  it "lets those who know the lore download the whole world" do
    get world_path(world)
    expect(response.body).to include("Export world") # the admin
    get world_package_path(world)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/zip")
    expect(response.headers["Content-Disposition"]).to include("base.world.zip")
    expect(PackageArchive.read(response.body, format: WorldPackage::FORMAT).data["name"]).to eq(world.name)

    sign_in_as(make_user("Stranger")) # not its editor, and no GM in it: its GM notes aren't theirs
    get world_package_path(world)
    expect(response).not_to have_http_status(:ok)
  end

  it "makes a new world from an uploaded package, owned by whoever uploaded it" do
    zip = WorldPackage::Export.new(world).to_zip
    ines = sign_in_as(make_user("Ines"))
    get worlds_path
    expect(response.body).to include("Import a world")
    get new_world_import_path
    expect(response.body).to include("World file")

    post world_import_path, params: { package_file: upload(zip), name: "Ines's World", slug: "ines_world" }
    copy = World.find_by!(slug: "ines_world")
    expect(response).to redirect_to(world_path(copy))
    expect(copy).to have_attributes(name: "Ines's World", owner: ines)
    expect(copy.monsters.count).to eq(world.monsters.count)
  end

  it "says what's wrong with a file that isn't a world" do
    sign_in_as(make_user("Ines"))
    post world_import_path, params: { package_file: upload("not a zip") }
    expect(response).to redirect_to(new_world_import_path)
    expect(flash[:alert]).to include("isn't a world")
  end
end

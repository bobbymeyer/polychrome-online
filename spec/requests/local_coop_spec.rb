# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Local co-op", type: :request do
  let(:campaign) { create_campaign.tap { |c| c.update!(gm: @admin) } }
  let!(:bartz) { create_character(campaign, name: "Bartz") }
  let!(:lenna) { create_character(campaign, name: "Lenna") }

  it "gives the GM a shared screen with a way to join, and remembers it until they leave" do
    get campaign_table_path(campaign)
    expect(response.body).to include("Local co-op", "Open the shared screen", "/join/#{campaign.reload.join_code}")

    get campaign_table_path(campaign, view: "screen")
    expect(response.body).to include('data-view="screen"', "table--screen", "<svg", "Code <strong>#{campaign.join_code}</strong>", "coop-party")
    expect(response.body).not_to include('id="composer"')

    get campaign_table_path(campaign)
    expect(response.body).to include("table--screen")
    get campaign_table_path(campaign, view: "off")
    expect(response.body).not_to include("table--screen")
  end

  it "shows the screen as a spectator sees it, even when the GM's laptop drives it" do
    campaign.map_nodes.create!(name: "Secret Grotto", x: 5, y: 5, visible: false)
    campaign.messages.create!(scope: "whisper", recipient: bartz, body: "Psst, the king is a fake")
    get campaign_table_path(campaign)
    expect(response.body).to include("Secret Grotto")

    get campaign_table_path(campaign, view: "screen")
    expect(response.body).not_to include("Secret Grotto", "the king is a fake", "Settle on this")
  end

  it "lets a player join from the code with just a name, and makes their phone a controller", :signed_out do
    code = campaign.join_code!
    get join_path(code.downcase)
    expect(response.body).to include("Bartz", "Lenna", "Your name")

    expect { post join_path(code), params: { name: "Sam", character_id: bartz.id } }.to change(User, :count).by(1)
    sam = User.last
    expect(sam).to have_attributes(name: "Sam", guest: true, admin: false)
    expect(bartz.reload.user).to eq(sam)
    expect(response).to redirect_to(campaign_table_path(campaign, view: "controller"))

    follow_redirect!
    expect(response.body).to include('data-view="controller"', "table--controller", "<h1>Bartz</h1>", "vitals", "My sheet")
    expect(response.body).not_to include("table__map", 'id="composer"')

    get join_path(code)
    expect(response.body).to include("Bartz", "yours", "Joining as <strong>Sam</strong>")
    expect(response.body).not_to include("Your name")
  end

  it "won't let someone join as a character that's taken, or with an old code", :signed_out do
    bartz.update!(user: make_user("Someone"))
    code = campaign.join_code!
    get join_path(code)
    expect(response.body).not_to include(">Bartz<")
    post join_path(code), params: { name: "Sneaky", character_id: bartz.id }
    expect(bartz.reload.user.name).to eq("Someone")

    campaign.new_join_code!
    get join_path(code)
    expect(response).to redirect_to(root_path)
  end

  it "shows the battle without commands on the screen, and commands without the show on a controller" do
    battle = start_battle(campaign: campaign)
    get battle_path(battle, view: "screen")
    expect(response.body).to include("battle--screen", "dialogue--battle")
    expect(response.body).not_to include('id="command_panel"')

    get battle_path(battle, view: "controller")
    expect(response.body).to include("battle--controller", 'id="command_panel"', "Leave controller view")
    expect(response.body).not_to include("dialogue--battle")
  end

  it "lets the GM shut old links out with a new code" do
    old = campaign.join_code!
    post campaign_join_code_path(campaign)
    expect(campaign.reload.join_code).not_to eq(old)
  end
end

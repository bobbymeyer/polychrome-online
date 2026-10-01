# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Local co-op", type: :request do
  let(:campaign) { create_campaign.tap { |c| c.update!(gm: @admin) } }
  let!(:bartz) { create_character(campaign, name: "Bartz") }
  let!(:lenna) { create_character(campaign, name: "Lenna") }

  it "gives the GM a shared screen with a way to join, and remembers it until they leave" do
    get campaign_table_path(campaign)
    expect(response.body).to include("Play around one screen", "Open the shared screen", "/join/#{campaign.reload.join_code}?view=controller")

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
    code = campaign.join_code
    get join_path(code.downcase, view: "controller")
    expect(response.body).to include("Bartz", "Lenna", "Your name", "This phone becomes your controller")

    # One form: picking Bartz sends the (empty) make-your-own fields too, and it's Bartz they get.
    characters = Character.count
    expect { post join_path(code), params: { name: "Sam", character_id: bartz.id, view: "controller", character: { name: "", motive: "" } } }
      .to change(User, :count).by(1)
    expect(Character.count).to eq(characters)
    sam = User.last
    expect(sam).to have_attributes(name: "Sam", guest: true, admin: false)
    expect(bartz.reload.user).to eq(sam)
    expect(response).to redirect_to(campaign_table_path(campaign, view: "controller"))
    expect(campaign.messages.last.body).to eq("Sam, as Bartz, joins the party.")

    follow_redirect!
    expect(response.body).to include('data-view="controller"', "table--controller", "<h1>Bartz</h1>", "vitals", "My sheet")
    expect(response.body).not_to include("table__map", 'id="composer"')

    expect { post join_path(code), params: { character_id: bartz.id } }.not_to(change { campaign.messages.count }) # back again: no new line
    get join_path(code)
    expect(response.body).to include("Bartz", "yours", "Joining as <strong>Sam</strong>")
    expect(response.body).not_to include("Your name")
  end

  it "shows what you're sitting down to before you join: the setting, and its lines and veils", :signed_out do
    campaign.world.update!(description: "A crystal world, going out.", lines: "Harm to children", veils: "Torture")
    get join_path(campaign.join_code)
    expect(response.body).to include("A crystal world, going out.", "Lines and veils", "Harm to children", "Torture")
    expect(response.body.index("Lines and veils")).to be < response.body.index("Play someone the GM made")
    expect(response.body.scan("Your name").size).to eq(1) # asked once, for picking or making
  end

  it "shows who's in the party while you pick an archetype, and who plays each", :signed_out do
    get join_path(campaign.join_code)
    expect(response.body).to include("In the party: Bartz (#{bartz.job.name}) and Lenna (#{lenna.job.name}).")
    expect(response.body).to match(/Bartz (and Lenna )?plays? this/)
  end

  it "won't let someone join as a character that's taken, or with an old code", :signed_out do
    bartz.update!(user: make_user("Someone"))
    code = campaign.join_code
    get join_path(code)
    expect(response.body).not_to include(">Bartz<")
    post join_path(code), params: { name: "Sneaky", character_id: bartz.id }
    expect(bartz.reload.user.name).to eq("Someone")

    campaign.new_join_code!
    get join_path(code)
    expect(response).to redirect_to(root_path)
  end

  it "shows the battle without commands on the screen, and commands without the show on a controller" do
    battle = start_battle(campaign: campaign, input_seconds: 30)
    get battle_path(battle, view: "screen")
    expect(response.body).to include("battle--screen", "dialogue--battle")
    get battle_panel_path(battle)
    expect(response.body).to include("screen-status", "Round 1", "data-countdown-deadline-value", "Waiting for Bartz and Lenna")
    expect(response.body).not_to include("menu__item", "Take a seat")

    battle.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "victory" }, actor: "gm")
    get battle_panel_path(battle)
    expect(response.body).to include("Victory!")
    expect(response.body).not_to include("Back to the table")

    get battle_path(battle, view: "controller")
    expect(response.body).to include("battle--controller", 'id="command_panel"', "Leave controller view")
    expect(response.body).not_to include("dialogue--battle")
  end

  it "lets the GM shut old links out with a new code" do
    old = campaign.join_code
    post campaign_join_code_path(campaign)
    expect(campaign.reload.join_code).not_to eq(old)
    expect(response).to redirect_to(campaign_path(campaign, anchor: "invite"))
  end

  describe "the invite" do
    it "is on the campaign page for the GM, with who has joined" do
      bartz.update!(user: make_user("Kim"))
      get campaign_path(campaign)
      expect(response.body).to include("Invite players", "/join/#{campaign.reload.join_code}", "Kim as Bartz", "Waiting for someone to play them: Lenna")
    end

    it "lets a friend make their own character when there's nobody to pick, and sits them at the table", :signed_out do
      empty = campaign.world.campaigns.create!(name: "Empty")
      code = empty.join_code
      get join_path(code)
      expect(response.body).to include("You&#39;re invited", "Make your character", "Starts with")
      expect(response.body).not_to include("Everyone here is taken")

      job = empty.available_jobs.first
      expect { post join_path(code), params: { name: "Sam", character: { name: "Faris", job_id: job.id, motive: "For my crew." } } }
        .to change(User, :count).by(1)
      faris = empty.characters.find_by!(name: "Faris")
      expect(faris).to have_attributes(user: User.last, level: Campaign::FIRST_LEVEL, motive: "For my crew.")
      expect(User.last.name).to eq("Sam")
      expect(empty.messages.last.body).to eq("Sam, as Faris, joins the party.")
      expect(response).to redirect_to(campaign_table_path(empty, view: "off"))
      follow_redirect!
      expect(response.body).to include("At the table as <strong>Faris</strong>")
    end

    it "joins a new character at the party's lowest level, and says what's missing", :signed_out do
      code = campaign.join_code
      bartz.update!(exp: Stats::Growth.exp_for_level(3))
      post join_path(code), params: { character: { name: "", job_id: campaign.available_jobs.first.id } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Name can&#39;t be blank")
      expect(User.count).to eq(User.where(guest: false).count) # nobody signed in for a character that wasn't made

      post join_path(code), params: { name: "Sam", character: { name: "Galuf", job_id: campaign.available_jobs.first.id } }
      expect(campaign.characters.find_by!(name: "Galuf").level).to eq(campaign.characters.minimum(:level))
    end
  end
end

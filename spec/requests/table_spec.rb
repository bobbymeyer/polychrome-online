# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The table", type: :request do
  let(:campaign) { create_campaign }
  let!(:bartz) { create_character(campaign, name: "Bartz") }
  let!(:lenna) { create_character(campaign, name: "Lenna") }
  let!(:cid) { campaign.npcs.create!(name: "Cid", title: "Engineer") }

  def sit(seat)
    post campaign_table_seat_path(campaign), params: { seat: seat }
  end

  def selected(id)
    Nokogiri::HTML(response.body).at("##{id} option[selected]")&.[]("value")
  end

  def say(fields)
    post campaign_messages_path(campaign), params: { message: fields }
  end

  it "offers seats, then subscribes each seat to its own streams only" do
    get campaign_table_path(campaign)
    expect(response.body).to include("Take a seat", "Game Master", "Bartz", "Lenna")
    expect(response.body.scan("<turbo-cable-stream-source").size).to eq(3) # table + players' map + the stage

    sit(bartz.id)
    get campaign_table_path(campaign)
    expect(response.body.scan("<turbo-cable-stream-source").size).to eq(4) # + Bartz's whispers
    expect(response.body).to include("At the table as <strong>Bartz</strong>")
    # The day clock: a slice per part of the day, turned so the part it is now is at the top.
    parts = campaign.almanac.periods
    expect(response.body).to include('class="day-clock"', %(data-day-clock-turn-value="#{-(campaign.parts_gone * 360.0 / parts.size)}"))
    expect(response.body.scan("day-clock__part--").size).to eq(parts.size)
  end

  describe "the GM" do
    before { sit("gm") }

    it "speaks as an NPC, with an expression, and keeps that speaker for the next line" do
      say(body: "Hold on!", speaker: "npc:#{cid.id}", expression: "surprised", whisper_to: "")
      line = campaign.messages.last
      expect(line).to have_attributes(speaker: cid, expression: "surprised", scope: "table", body: "Hold on!")
      expect(selected("message_speaker")).to eq("npc:#{cid.id}")
      expect(selected("message_expression")).to eq("surprised")
    end

    it "narrates" do
      say(body: "Wind howls.", speaker: "narrator", expression: "neutral")
      expect(campaign.messages.last.speaker).to be_nil
    end

    it "whispers to one player, then goes back to speaking to everyone" do
      say(body: "Psst.", speaker: "narrator", whisper_to: bartz.id)
      expect(campaign.messages.last).to have_attributes(scope: "whisper", recipient: bartz)
      expect(selected("message_whisper_to").to_s).to eq("") # nothing selected: the first option, Everyone
    end

    it "sees every whisper in the log" do
      campaign.messages.create!(body: "Only the GM hears this", scope: "whisper", speaker: lenna)
      get campaign_table_path(campaign)
      expect(response.body).to include("Only the GM hears this", "whispers to the GM")
    end

    it "can't speak as another campaign's NPC" do
      other = create_campaign(world: campaign.world, name: "Other").npcs.create!(name: "Spy")
      say(body: "Hi", speaker: "npc:#{other.id}")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "a player" do
    before { sit(bartz.id) }

    it "always speaks as their own character, whatever the params say" do
      say(body: "Hi!", speaker: "npc:#{cid.id}", expression: "happy")
      expect(campaign.messages.last).to have_attributes(speaker: bartz, expression: "happy", scope: "table")
    end

    it "whispers only to the GM" do
      say(body: "I pocket it.", whisper_to: "gm")
      expect(campaign.messages.last).to have_attributes(scope: "whisper", speaker: bartz, recipient: nil)
      say(body: "Hey Lenna", whisper_to: lenna.id)
      expect(campaign.messages.last).to have_attributes(scope: "table", body: "Hey Lenna")
    end

    it "sees their own whispers but not anyone else's" do
      campaign.messages.create!(body: "For Bartz", scope: "whisper", recipient: bartz)
      campaign.messages.create!(body: "For Lenna", scope: "whisper", recipient: lenna)
      campaign.messages.create!(body: "Lenna to GM", scope: "whisper", speaker: lenna)
      get campaign_table_path(campaign)
      expect(response.body).to include("For Bartz")
      expect(response.body).not_to include("For Lenna", "Lenna to GM")
    end

    it "gets the composer back with errors for an empty line" do
      say(body: "   ")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Body can&#39;t be blank")
    end
  end

  it "won't take a message from someone without a seat" do
    say(body: "Hello?")
    expect(response).to have_http_status(:forbidden)
  end

  it "keeps the log in a drawer, closed until it's opened" do
    campaign.messages.create!(body: "The road is long.", speaker: cid)
    get campaign_table_path(campaign)
    drawer = response.body[/<div class="log-drawer".*?<\/aside>/m]
    expect(drawer).to include('id="chat_log"', "The road is long.", "inert", 'aria-expanded="false"')
  end

  it "shows the last GM line in the dialogue box on arrival, without replaying anything" do
    campaign.messages.create!(body: "Old news.", speaker: cid)
    campaign.messages.create!(body: "Player chatter.", speaker: bartz)
    get campaign_table_path(campaign)
    box = response.body[/<section class="dialogue window".*?<\/section>/m]
    expect(box).to include("Cid", "Old news.")
    expect(box).not_to include("Player chatter.")
  end

  it "gives the narrator the whole box, and a speaker's name tag their colour" do
    campaign.messages.create!(body: "Rain on the roofs.")
    get campaign_table_path(campaign)
    box = response.body[/<section class="dialogue window.*?<\/section>/m]
    expect(box).to include("is-narration", "Rain on the roofs.")
    expect(box).not_to include("speaker-portrait")

    campaign.messages.create!(body: "Hm.", speaker: cid)
    get campaign_table_path(campaign)
    box = response.body[/<section class="dialogue window.*?<\/section>/m]
    expect(box).not_to include("is-narration")
    expect(box).to include("speaker-portrait", 'class="dialogue__name" data-dialogue-target="name" style="--plate: ')
  end

  it "puts the date up top, with the days left on the clocks a new day ticks, and story time in the log" do
    campaign.update!(day: 3, time_of_day: "dusk")
    campaign.clocks.create!(name: "The spring tide comes in", segments: 6, filled: 1, triggers: %w[dawn], public: true)
    campaign.clocks.create!(name: "The count schemes", segments: 4, triggers: %w[dawn], public: false)
    campaign.clocks.create!(name: "The guard grows wary", segments: 4, triggers: %w[rest dawn], public: true)
    campaign.messages.create!(body: "Lanterns.", speaker: cid)
    get campaign_table_path(campaign)
    header = response.body[/<header class="battle__header">.*?<\/header>/m]
    expect(header).to include("Day 3", "time--dusk", "5 days</strong> The spring tide comes in")
    expect(header).not_to include("The count schemes", "The guard grows wary")
    campaign.clocks.find_by!(name: "The spring tide comes in").update!(filled: 5)
    get campaign_table_path(campaign)
    expect(response.body).to include(%(<li class="is-tomorrow"><strong>Tomorrow</strong> The spring tide comes in</li>))
    expect(response.body).to match(%r{<time class="muted" datetime="[^"]+" title="Day 3 · [^"]+">Dusk</time>})
  end

  describe "battles" do
    it "announce their start and their outcome at the table, with a link" do
      battle = start_battle(campaign: campaign)
      expect(campaign.messages.last).to have_attributes(kind: "system", battle: battle)
      expect(campaign.messages.last.body).to include("Test battle begins: Bartz and Lenna against 2 × Goblin.")

      battle.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "victory" }, actor: "gm")
      expect(campaign.messages.last.body).to start_with("Test battle: Victory! 10 gil.")

      sit(lenna.id)
      get campaign_table_path(campaign)
      expect(response.body).to include("See the battle")
    end

    it "carry the table seat over, until the player leaves the battle seat" do
      battle = start_battle(campaign: campaign)
      sit(lenna.id)
      get battle_panel_path(battle)
      expect(response.body).to include("Seated as <strong>Lenna</strong>")

      delete battle_seat_path(battle)
      get battle_panel_path(battle)
      expect(response.body).to include("Take a seat")
    end
  end

  describe "the cast" do
    let(:image) { Rack::Test::UploadedFile.new(file_fixture("goblin.png"), "image/png") }

    it "creates NPCs with portraits, and edits and removes them" do
      post campaign_npcs_path(campaign), params: { npc: { name: "Galuf", title: "Old man" }, portraits: { images: { "neutral" => image } } }
      galuf = campaign.npcs.find_by!(name: "Galuf")
      expect(galuf.portrait_image("happy")).to be_present

      patch npc_path(galuf), params: { npc: { name: "Galuf", title: "Amnesiac" }, portraits: { remove: [ "neutral" ] } }
      expect(galuf.reload).to have_attributes(title: "Amnesiac")
      expect(galuf.portraits).to be_empty

      campaign.messages.create!(body: "Where am I?", speaker: galuf)
      delete npc_path(galuf)
      expect(campaign.messages.last.speaker).to be_nil
    end

    it "gives characters portraits too" do
      patch character_path(bartz), params: { character: { name: "Bartz" }, portraits: { images: { "determined" => image } } }
      expect(bartz.portraits.pluck(:expression)).to eq([ "determined" ])
    end
  end

  it "offers a recap of the last session, once there is one" do
    get campaign_table_path(campaign)
    expect(response.body).not_to include("Previously on")

    campaign.messages.create!(speaker: cid, body: "The crystal is cracking.", created_at: 2.days.ago)
    get campaign_table_path(campaign)
    expect(response.body).to include("Previously on The Crystal Road…", 'data-controller="dialogue recap moment"', "The crystal is cracking.",
                                     'data-recap-auto-value="true"')
  end

  it "keeps the recap of the session still going to its link, never popping up by itself" do
    campaign.messages.create!(speaker: cid, body: "The crystal is cracking.", created_at: 10.minutes.ago)
    get campaign_table_path(campaign)
    expect(response.body).to include("Previously on The Crystal Road…", 'data-recap-auto-value="false"')
  end

  describe "taking a line back" do
    it "lets the GM take back any line said, for everyone, but not what the game logged" do
      sit("gm")
      line = campaign.messages.create!(speaker: cid, body: "Typo'd lnie")
      logged = campaign.messages.create!(kind: "system", body: "The party rests.")
      get campaign_table_path(campaign)
      expect(response.body).to include('data-retract="all"', "Take back")

      expect { delete message_path(line) }.to have_broadcasted_to(stream(campaign, :table)).with(a_string_including('action="remove"', "message_#{line.id}"))
      expect(Message.exists?(line.id)).to be(false)
      delete message_path(logged)
      expect(Message.exists?(logged.id)).to be(true)
    end

    it "lets a player take back only their own lines" do
      sit(bartz.id)
      mine = campaign.messages.create!(speaker: bartz, body: "Oops")
      theirs = campaign.messages.create!(speaker: lenna, body: "Mine")
      get campaign_table_path(campaign)
      expect(response.body).to include("data-retract=\"Character:#{bartz.id}\"")
      delete message_path(theirs)
      expect(Message.exists?(theirs.id)).to be(true)
      delete message_path(mine)
      expect(Message.exists?(mine.id)).to be(false)
    end
  end

  describe "choices" do
    it "are put to the table by the GM, picked by players as themselves, and settled by the GM" do
      sit("gm")
      post campaign_messages_path(campaign), params: { message: { body: "? Trust Cid | Refuse -> trusted_cid", speaker: "narrator" } }
      choice = campaign.open_choice
      expect(choice.options).to eq([ "Trust Cid", "Refuse" ])
      get campaign_table_path(campaign)
      expect(response.body).to include('data-seat="gm"', "What will the party do?", "Settle on this")

      post choice_picks_path(choice), params: { option: "Refuse" }
      expect(choice.picks).to be_empty # the GM doesn't pick

      sit(bartz.id)
      post choice_picks_path(choice), params: { option: "Refuse" }
      expect(choice.reload.tally["Refuse"]).to eq([ "Bartz" ])
      post choice_settlement_path(choice), params: { option: "Refuse" }
      expect(choice.reload.settled).to be_nil # players don't settle

      sit("gm")
      post choice_settlement_path(choice), params: { option: "Refuse" }
      expect(choice.reload.settled).to eq("Refuse")
      expect(campaign.flags.find_by!(key: "trusted_cid").value).to eq("Refuse")
    end
  end

  describe "checks" do
    it "are called by the GM: each character rolls from the campaign's RNG, and the table sees it land" do
      sit("gm")
      get campaign_table_path(campaign)
      expect(response.body).to include("gm_tab_check", "Who tries")

      rng = campaign.rng
      post campaign_checks_path(campaign), params: { check: { characters: [ bartz.id, lenna.id ], stat: "agi", difficulty: "hard", reason: "scale the wall" } }
      lines = campaign.messages.where(cue: "check").chronological
      expect(lines.map(&:body)).to all(match(/Agi check \(hard\) to scale the wall\. \d+% · rolled \d+ · (Success!|Failure\.)/))
      expect(lines.first.data).to include("name" => "Bartz", "stat" => "agi", "difficulty" => "hard")
      expect(campaign.reload.rng).not_to eq(rng)

      get campaign_table_path(campaign)
      expect(response.body).to include("check-roll", "data-check-roll-result-value")

      sit(bartz.id)
      expect { post campaign_checks_path(campaign), params: { check: { characters: [ bartz.id ], stat: "agi", difficulty: "easy" } } }
        .not_to(change { campaign.messages.count })
    end
  end
end

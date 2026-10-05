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

  def field(id) = Nokogiri::HTML(response.body).at("##{id}")&.[]("value")

  def pressed = Nokogiri::HTML(response.body).css(".composer__chip[aria-pressed=true]").map(&:text)

  def now = Nokogiri::HTML(response.body).at("#table_now").text.squish

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
    expect(Nokogiri::HTML(response.body).at("#table_party li.is-you").text).to include("Bartz")
    # The day clock: a slice per part of the day, turned so the part it is now is at the top.
    parts = campaign.almanac.periods
    expect(response.body).to include('class="day-clock"', %(data-day-clock-turn-value="#{-(campaign.parts_gone * 360.0 / parts.size)}"))
    expect(response.body.scan("day-clock__part--").size).to eq(parts.size)
    expect(response.body).to include("day-clock__ring") # one outline with the label beside it
  end

  describe "the GM" do
    before { sit("gm") }

    it "speaks as an NPC, with an expression, and keeps that speaker for the next line" do
      say(body: "Hold on!", speaker: "npc:#{cid.id}", expression: "surprised", whisper_to: "")
      line = campaign.messages.last
      expect(line).to have_attributes(speaker: cid, expression: "surprised", scope: "table", body: "Hold on!")
      expect(field("message_speaker")).to eq("npc:#{cid.id}")
      expect(pressed).to eq([ "Cid" ]) # the chip, kept for the next line
      expect(selected("message_expression")).to eq("surprised")
    end

    it "speaks as whoever a line names, with their face, the way a script does" do
      say(body: "Cid (angry): Behind you!", speaker: "narrator", expression: "neutral")
      expect(campaign.messages.last).to have_attributes(speaker: cid, expression: "angry", body: "Behind you!")
      expect(pressed).to eq([ "Cid" ])
      say(body: "Narrator: Wind howls.", speaker: "npc:#{cid.id}")
      expect(campaign.messages.last).to have_attributes(speaker: nil, body: "Wind howls.")
      expect(pressed).to eq([ "Narrator" ])
      say(body: "Yes: go.", speaker: "narrator") # not a name in the cast: the line is what was typed
      expect(campaign.messages.last).to have_attributes(speaker: nil, body: "Yes: go.")
    end

    it "speaks as the scene's speaker while a scene is on the stage, until the GM says Narrator" do
      scene = campaign.scenes.create!(name: "Ambush", script: "Cid (angry): Behind you!\nNarrator: Silence.")
      get campaign_composer_path(campaign)
      expect(pressed).to eq([ "Narrator" ]) # no scene: the narrator
      expect(response.body).not_to include("message_speaker\" value=\"npc") # no select of every NPC
      scene.reload.start!
      get campaign_composer_path(campaign)
      expect(pressed).to eq([ "Cid" ]) # the line on the stage is Cid's
      expect(field("message_speaker")).to eq("npc:#{cid.id}")
      say(body: "Narrator: The lamp gutters.", speaker: "npc:#{cid.id}")
      expect(campaign.messages.last.speaker).to be_nil
      expect(pressed).to eq([ "Narrator" ]) # chosen over the scene, it stays
      expect(Nokogiri::HTML(response.body).css(".composer__chip").map(&:text)).to eq(%w[Narrator Cid]) # Cid is a press away
    end

    it "narrates" do
      say(body: "Wind howls.", speaker: "narrator", expression: "neutral")
      expect(campaign.messages.last.speaker).to be_nil
    end

    it "whispers to one player from the party panel, then goes back to speaking to everyone" do
      get campaign_table_path(campaign)
      whispers = Nokogiri::HTML(response.body).css("#table_party .coop-party__whisper")
      expect(whispers.map { |b| b["data-character-name"] }).to eq(%w[Bartz Lenna]) # the GM's, beside each played character
      expect(response.body).not_to include("message_whisper_to\" value=\"", "Whisper to Bartz</option>") # no select
      say(body: "Psst.", speaker: "narrator", whisper_to: bartz.id)
      expect(campaign.messages.last).to have_attributes(scope: "whisper", recipient: bartz)
      expect(field("message_whisper_to").to_s).to eq("") # back to everyone
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

    it "has their moves together, themselves up top, and says who hears what they say" do
      bartz.update!(motive: "My sister's debt is mine now.")
      get campaign_table_path(campaign)
      page = Nokogiri::HTML(response.body)
      moves = page.at("section.your-moves")
      expect(moves.text).to include("Your moves")
      expect(moves.at("#table_choice")).to be_present
      expect(moves.at("#composer")).to be_present
      you = page.at("#table_party li.is-you") # your own row, first in the party
      expect(you.text.squish).to include("Bartz", "Lv 5 Knight", "My sister's debt is mine now.")
      expect(page.css("#table_party .coop-party__list li").first).to eq(you)
      expect(you.at(".vitals")["id"]).to be_present # the row broadcasts look for
      # Three columns: you and the party on the left, the stage over the controls in the middle, the log on the right.
      expect(page.at(".table__side #table_party li.is-you")).to be_present
      expect(page.at(".table__side #drawer_party")).to be_present
      expect(page.at(".table__stage #stage #table_scene")).to be_present # the stage, in the middle
      expect(page.at(".table__stage .table-controls #table_now")).to be_present # the controls under it
      expect(page.at(".table-controls .your-moves #table_choice")).to be_present
      expect(page.at(".table-controls .gm-tools")).to be_nil # a player has no GM tools
      expect(page.at(".recent-lines")).to be_nil # the log is the record
      expect(page.at("#stage .dialogue")).to be_present # what's said plays on it
      expect(page.at(".log-drawer")["data-log-drawer-pin-from-value"]).to eq("1100")
      expect(page.css("##{ActionView::RecordIdentifier.dom_id(bartz, :vitals)}").size).to eq(1)

      get campaign_composer_path(campaign)
      expect(response.body).to include("Everyone at the table hears it, said as Bartz. Whispered, only the GM does.")
    end

    it "shows what they can do now, and keeps the rest a tap away" do
      get campaign_table_path(campaign)
      page = Nokogiri::HTML(response.body)
      expect(page.at("#table_now")["data-state"]).to eq("free")
      expect(page.at("details.talk summary").text).to eq("Say something") # talk is a button until it's wanted
      expect(page.at("details.talk #composer")).to be_present
      %w[party knows].each { |key| expect(page.at("#drawer_#{key}")["hidden"]).not_to be_nil } # looked up, not shown
      expect(page.at("#stage #table_map")["hidden"]).not_to be_nil # the map waits on the stage until the GM shows it
      expect(page.at("#stage #table_time")).to be_present # the date in its corner
      expect(page.at("#drawer_party #table_party")).to be_present
      menu = page.at(".topbar__user-menu")
      expect(menu.text).to include("At the table as Bartz", "Stand up") # the seat is in the account menu, with the others to take
      expect(menu.css("form button").map(&:text)).not_to include("Sit as Bartz") # not the one you're in

      Message.choice(campaign, options: [ "Trust Cid", "Refuse" ]).save!
      get campaign_table_path(campaign)
      expect(Nokogiri::HTML(response.body).at("#table_now")["data-state"]).to eq("choice")
    end

    it "keeps the talk box for Talk: the Now line says which controls are called, and the rest follows it" do
      sit(bartz)
      get campaign_table_path(campaign)
      page = Nokogiri::HTML(response.body)
      expect(page.at("#table_now")["data-controls"]).to eq("talk")
      expect(page.at(".table-talk #composer")).to be_present

      campaign.call_controls!("travel")
      get campaign_table_path(campaign)
      page = Nokogiri::HTML(response.body)
      expect(page.at("#table_now")["data-controls"]).to eq("travel") # stage.css hides .table-talk and the whispers under it
      expect(page.at(".table-talk #composer")).to be_present
    end

    it "always speaks as their own character, whatever the params say" do
      say(body: "Hi!", speaker: "npc:#{cid.id}", expression: "happy")
      expect(campaign.messages.last).to have_attributes(speaker: bartz, expression: "happy", scope: "table")
    end

    it "whispers only to the GM, from two chips, and has no Whisper beside the party" do
      get campaign_table_path(campaign)
      expect(Nokogiri::HTML(response.body).css("#table_party .coop-party__whisper")).to be_empty
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
    box = response.body[/<section class="dialogue window dialogue--stage".*?<\/section>/m]
    expect(box).to include("Cid", "Old news.")
    expect(box).not_to include("Player chatter.")

    # Once the party has moved on, it was said somewhere else: the box doesn't keep it up.
    campaign.place_party!(campaign.map_nodes.create!(name: "Walse", kind: "town", x: 5, y: 5, visible: true))
    get campaign_table_path(campaign)
    box = response.body[/<section class="dialogue window.*?<\/section>/m]
    expect(box).to include("hidden")
    expect(box).not_to include("Old news.")
    expect(response.body).to include("data-moved") # and a page that's open puts it away as the move arrives
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

  it "puts the date on the stage, with the days left on the clocks a new day ticks, and story time in the log" do
    campaign.update!(day: 3, time_of_day: "dusk")
    campaign.clocks.create!(name: "The spring tide comes in", segments: 6, filled: 1, triggers: %w[dawn], public: true)
    campaign.clocks.create!(name: "The count schemes", segments: 4, triggers: %w[dawn], public: false)
    campaign.clocks.create!(name: "The guard grows wary", segments: 4, triggers: %w[rest dawn], public: true)
    campaign.messages.create!(body: "Lanterns.", speaker: cid)
    get campaign_table_path(campaign)
    header = response.body[/<div class="stage__hud">.*?<\/section>/m] # the date, in the stage's corner
    expect(header).to include("Day 3", "time--dusk", "5 days</strong> until The spring tide comes in")
    expect(header).not_to include("The count schemes", "The guard grows wary")
    campaign.update!(current_node: campaign.map_nodes.create!(name: "Varn", x: 10, y: 10, visible: true))
    get campaign_table_path(campaign)
    expect(Nokogiri::HTML(response.body).at("#table_time .table-time__where").text.squish).to eq("Varn") # where, beside when
    campaign.clocks.find_by!(name: "The spring tide comes in").update!(filled: 5)
    get campaign_table_path(campaign)
    expect(response.body).to include(%(<li class="is-tomorrow"><strong>Tomorrow</strong> it happens: The spring tide comes in</li>))
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

    it "gives characters portraits too, from the sheet's Look panel, with nothing else of theirs in the post" do
      patch character_path(bartz), params: { portraits: { images: { "determined" => image } } }
      expect(response).to redirect_to(character_path(bartz, anchor: "look"))
      expect(bartz.portraits.pluck(:expression)).to eq([ "determined" ])
      expect(bartz.reload.name).to eq("Bartz")
    end
  end

  it "offers a recap of the last session, once there is one" do
    get campaign_table_path(campaign)
    expect(response.body).not_to include("Previously on")

    campaign.messages.create!(speaker: cid, body: "The crystal is cracking.", created_at: 2.days.ago)
    get campaign_table_path(campaign)
    expect(response.body).to include("Previously on The Crystal Road…", 'data-controller="dialogue recap moment whisper-toast table-views"', "The crystal is cracking.",
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

  describe "the Now line" do
    it "says what the table is doing and whose move it is, to the GM and to the players" do
      sit("gm")
      get campaign_table_path(campaign)
      expect(now).not_to include("The table is yours.", "Now") # in free play the GM's line is the controls row alone
      expect(now).to eq("Talk Travel Things to do here Scene Check Battle GM tools")

      Message.choice(campaign, options: [ "Trust Cid", "Refuse" ]).save!
      get campaign_table_path(campaign)
      expect(now).to include("The party is choosing.", "Settle it when you're ready.")
      expect(now).not_to include("Nobody has picked yet.") # who has picked is the vote's own footer
      expect(Nokogiri::HTML(response.body).at("#table_choice .choice__footer").text.squish).to eq("Nobody has picked yet. Nobody plays Bartz and Lenna: no pick from them.")

      sit(bartz.id)
      post choice_picks_path(campaign.open_choice), params: { option: "Refuse" }
      get campaign_table_path(campaign)
      expect(now).to include("Pick below; the GM settles it.")
      expect(Nokogiri::HTML(response.body).at("#table_choice .choice__footer").text.squish).to eq("Picked: Bartz. Nobody plays Lenna: no pick from them.")
    end

    it "puts a battle first: the choice waits, and can't be settled until it's over" do
      choice = Message.choice(campaign, options: [ "Trust Cid", "Refuse" ])
      choice.save!
      battle = start_battle(campaign: campaign)
      sit("gm")
      get campaign_table_path(campaign)
      expect(now).to include("A battle is on: #{battle.name}.", "The choice waits until it's over.", "Go to the battle")
      expect(response.body).to include("On hold until the battle is over.")

      post choice_settlement_path(choice), params: { option: "Refuse" }
      expect(choice.reload.settled).to be_nil
    end
  end

  describe "who is at the table" do
    def party = Nokogiri::HTML(response.body).at("#table_party").text.squish

    it "says who nobody plays, and who is here or away, from a heartbeat the table and battles send" do
      bartz.update!(user: make_user("Kim"))
      get campaign_table_path(campaign)
      expect(party).to include("Kim away", "unplayed")

      sit(bartz.id)
      get campaign_table_path(campaign)
      expect(response.body).to include("heartbeat", campaign_presence_path(campaign))
      patch campaign_presence_path(campaign)
      expect(response).to have_http_status(:no_content)
      expect(bartz.reload).to be_here
      get campaign_table_path(campaign)
      expect(party).to include("Kim here")

      travel Character::HERE_FOR + 1.second
      expect(bartz.reload).not_to be_here
    end

    it "gives the GM no player's tag or You line, and says who hears a whisper" do
      sit("gm")
      get campaign_table_path(campaign)
      expect(response.body).not_to include("your-moves__tag", "table-you")
      get campaign_composer_path(campaign)
      expect(response.body).to include("Everyone hears it. Start a line with a name and a colon to speak as them", "Whisper from the party panel.")
    end

    it "gives the GM the moves for what's happening, in the Now line, with the rest of the tools behind Tools" do
      sit("gm")
      get campaign_table_path(campaign)
      page = Nokogiri::HTML(response.body)
      expect(page.css("#table_now .controls-call button").map(&:text)).to eq([ "Talk", "Travel", "Things to do here", "Scene", "Check", "Battle" ])
      expect(page.at("#table_now .table-now__do").text).not_to include("Call a check", "Play a scene") # no second way in
      expect(page.css(".gm-tools [role=tab]").map { |t| t.text.strip }).to eq(%w[Moves More]) # the rest is called, or Prep's
      expect(page.at("#table_now .table-now__do button[data-gm-tools-toggle]").text).to eq("GM tools") # after the row; the tools fold until pressed
      expect(page.at("#table_called").key?("hidden")).to be(true) # nothing called
      %w[party knows].each { |key| expect(page.at("#drawer_#{key}")).to be_present } # what the GM looks up, in tabs
      expect(page.at(".table__stage #stage #table_map")["hidden"]).not_to be_nil # the map, until the GM shows it
      expect(page.at("#drawer_knows #party_knows")).to be_present

      Message.choice(campaign, options: [ "Trust Cid", "Refuse" ]).save!
      get campaign_table_path(campaign)
      expect(Nokogiri::HTML(response.body).at("#table_now .table-now__do a[href='#table_choice']").text).to eq("Settle it ↓")
    end

    it "marks what only the GM sees" do
      campaign.map_nodes.create!(name: "Secret Grotto", x: 5, y: 5, visible: false)
      campaign.clocks.create!(name: "The tide", segments: 4, public: true)
      sit("gm")
      get campaign_table_path(campaign)
      expect(response.body).to include("GM tools</button>", "gm_tab_more", "Grant an archetype", "Music for the table")
      expect(response.body).not_to include("only you see these") # the button's name says who sees them
      get campaign_maps_path(campaign)
      expect(response.body).to include("Secret Grotto", "Hidden from the players") # the maps page, the GM's
      sit(bartz.id)
      get campaign_table_path(campaign)
      expect(response.body).not_to include("only you see", "Everyone at the table sees this.")
    end
  end

  describe "checks" do
    it "are called by the GM: each character rolls from the campaign's RNG, and the table sees it land" do
      sit("gm")
      get campaign_table_path(campaign)
      expect(response.body).not_to include("Who tries") # until Check is called
      campaign.call_controls!("check")
      get campaign_table_path(campaign)
      called = Nokogiri::HTML(response.body).at("#table_called")
      expect(called.key?("hidden")).to be(false)
      expect(called.text).to include("Who tries", "Everyone standing")
      expect(called.to_html).to include('data-controller="check-all"')

      rng = campaign.rng
      post campaign_checks_path(campaign), params: { check: { characters: [ bartz.id, lenna.id ], stat: "agi", difficulty: "hard", reason: "scale the wall" } }
      lines = campaign.messages.where(cue: "check").chronological
      expect(lines.map(&:body)).to all(match(/Agi check \(hard\) to scale the wall\. needed 66 or over · rolled \d+( [+−]\d+ Agi = -?\d+)? · (Success!|Failure\.)/))
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

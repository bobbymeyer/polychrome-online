# frozen_string_literal: true

require "rails_helper"
require "turbo/broadcastable/test_helper"

RSpec.describe "Battle screen", type: :request do
  include Turbo::Broadcastable::TestHelper

  let(:battle) { start_battle }
  let(:bartz) { battle.party.first.id }
  let(:faris) { battle.party.second.id }

  def command!(params)
    post battle_actions_path(battle), params: { command: params }
  end

  def gm!(params)
    post battle_actions_path(battle), params: { gm: params }
  end

  it "brings the table along: its log in the drawer, and a dialogue box for whatever is said" do
    cid = battle.campaign.npcs.create!(name: "Cid", title: "Engineer")
    battle.campaign.messages.create!(body: "Hold the line!", speaker: cid)
    get battle_path(battle)
    drawer = page.at(".log-drawer")
    expect(drawer.at("#chat_log")).to be_present
    expect(drawer.text).to include("Battle", "Hold the line!")
    expect(page.at("section.dialogue.dialogue--battle[aria-label=Dialogue]").key?("hidden")).to be(true) # nothing said yet in this battle
    expect(response.body).to include(Turbo::StreamsChannel.signed_stream_name([ battle.campaign, :table ]))
  end

  it "reports the battle's numbers to the GM, and to nobody else" do
    goblin = battle.state["units"].find { |u| u["side"] == "enemy" }["id"]
    battle.apply!({ "type" => "command", "actor" => bartz, "command" => { "kind" => "ability", "ability" => "attack", "target" => goblin } }, actor: "gm")
    battle.apply!({ "type" => "command", "actor" => faris, "command" => { "kind" => "ability", "ability" => "attack", "target" => goblin } }, actor: "gm")
    report = battle.reload.report

    get battle_path(battle)
    expect(page.at("a[href='#{battle_report_path(battle)}']").text).to eq("Report")
    get battle_report_path(battle)
    expect(response).to have_http_status(:ok)
    party = page.css(".battle-report__side").first
    expect(party.at("h2").text).to eq("The party")
    bartz_row = party.css("tbody tr").find { |tr| tr.at("th").text == "Bartz" }
    expect(bartz_row.css("td").first.text.to_i).to eq(report["units"].find { |r| r["id"] == bartz }["dealt"]).and be_positive
    expect(bartz_row.text).to include("Attack ×1")
    expect(page.at(".battle-report__rounds tbody tr th").text).to eq("1")

    # A table a file, for a spreadsheet.
    expect(page.css(".battle-report__download a").map(&:text)).to eq(%w[Fighters Rounds Moves])
    get battle_report_path(battle, format: :csv, table: "fighters")
    expect(response.media_type).to eq("text/csv")
    expect(response.headers["Content-Disposition"]).to include("test-battle-fighters.csv")
    fighters = CSV.parse(response.body, headers: true)
    expect(fighters.headers).to include("Side", "Who", "Kind", "Dealt", "HP left", "Used")
    expect(fighters.find { |r| r["Who"] == "Bartz" }.to_h).to include("Side" => "Party", "Dealt" => report["units"].find { |r| r["id"] == bartz }["dealt"].to_s)
    expect(fighters.find { |r| r["Who"] == "Goblin A" }["Kind"]).to eq("Goblin")
    get battle_report_path(battle, format: :csv, table: "rounds")
    expect(CSV.parse(response.body)).to eq([ [ "Round", "The party dealt", "The enemies dealt" ], *report["by_round"].map { |r| r.values_at("round", "party", "enemy").map(&:to_s) } ])
    get battle_report_path(battle, format: :csv, table: "nonsense")
    expect(CSV.parse(response.body).first.first).to eq("Side") # the fighters, for a table it doesn't know

    sign_in_as(make_user("Player"))
    get battle_report_path(battle)
    expect(response).to redirect_to(root_path)
    get battle_report_path(battle, format: :csv)
    expect(response).to have_http_status(:forbidden)
  end

  it "puts the campaign's battles together for the GM, from Prep" do
    goblin = battle.state["units"].find { |u| u["side"] == "enemy" }["id"]
    battle.apply!({ "type" => "command", "actor" => bartz, "command" => { "kind" => "ability", "ability" => "attack", "target" => goblin } }, actor: "gm")
    battle.apply!({ "type" => "command", "actor" => faris, "command" => { "kind" => "ability", "ability" => "attack", "target" => goblin } }, actor: "gm")
    campaign = battle.campaign
    second = start_battle(campaign: campaign, goblins: 1)

    get campaign_prep_path(campaign)
    expect(page.at("a[href='#{campaign_battle_report_path(campaign)}']").text).to eq("Battle report")
    get campaign_battle_report_path(campaign)
    expect(response).to have_http_status(:ok)
    rows = page.css(".battle-report__battles tbody tr")
    expect(rows.map { |tr| tr.at("th a")[:href] }).to eq([ battle_report_path(second), battle_report_path(battle) ]) # newest first
    expect(rows.last.text).to include("2 × Goblin")
    goblins = page.css(".battle-report__side").last.css("tbody tr").find { |tr| tr.at("th").text == "Goblin" }
    expect(goblins.css("td").first(2).map(&:text)).to eq(%w[2 3]) # in both battles, three of them faced
    expect(page.at(".battle-report__moves tbody").text).to include("Attack")

    get campaign_battle_report_path(campaign, format: :csv)
    expect(response.headers["Content-Disposition"]).to include("#{campaign.name.parameterize}-battles.csv")
    battles = CSV.parse(response.body, headers: true)
    expect(battles.map { |r| r["Result"] }).to eq([ "Under way", "Under way" ])
    expect(battles.to_a.last.last).to eq("2 × Goblin")
    get campaign_battle_report_path(campaign, format: :csv, table: "fighters")
    expect(CSV.parse(response.body, headers: true).find { |r| r["Who"] == "Goblin" }.to_h).to include("Side" => "Enemy", "Battles" => "2", "Faced" => "3")
    get campaign_battle_report_path(campaign, format: :csv, table: "moves")
    expect(CSV.parse(response.body, headers: true).map { |r| r["Move"] }).to include("Attack")

    sign_in_as(make_user("Player"))
    get campaign_battle_report_path(campaign)
    expect(response).to redirect_to(root_path)
  end

  it "lets the seated speak from the battle, and takes back lines there too" do
    sit(battle.campaign, "gm")
    get battle_path(battle)
    expect(response.body).to include("battle-composer", campaign_composer_path(battle.campaign))
    expect(page.at("[data-retract=all]")).to be_present
    expect(page.at("[data-menu-key=Talk]")).to be_nil # the GM's panel has no commands
  end

  it "tells the GM how a fight is likely to go, as they set it up" do
    campaign = create_campaign
    create_character(campaign, name: "Bartz")
    get new_campaign_battle_path(campaign) # the old page's address calls Battle at the table
    expect(response).to redirect_to(campaign_table_path(campaign))
    expect(campaign.reload.controls).to eq("battle")
    at_the_table(campaign, as: "gm")
    setup = page.at("#table_called .battle-setup")
    expect(setup["data-controller"].split).to include("forecast", "help")
    expect(setup.at("#forecast")).to be_present
    expect(setup.css("option").map(&:text)).to include(match(/\AGoblin \(\d+ HP\)\z/)) # how tough, not the book's level
    expect(setup.text).not_to include("(Lv ")
    expect(setup.css("fieldset legend").map(&:text)).to eq([ "What they face", "Who fights" ])
    expect(setup.at("details.battle-setup__more").text).to include("Input timer", "Seed", "Can flee") # the rest, behind More

    get campaign_forecast_path(campaign), params: { battle: { encounter: { "0" => { monster: "goblin", count: "1" } } } }
    expect(response.body).to match(/forecast--(easy|fair|hard|deadly)/)
    expect(response.body).to include("Played out 20 times")

    get campaign_forecast_path(campaign), params: { battle: { encounter: { "0" => { monster: "", count: "1" } } } }
    expect(response.body).to include("Pick who fights")
  end

  it "lets a player put themselves on auto, and only themselves" do
    sit_in_battle(battle, bartz)
    battle.set_auto!(bartz, false) # unclaimed characters start on auto
    get battle_panel_path(battle)
    expect(response.body).to include("Go on auto")
    patch battle_auto_path(battle), params: { unit: faris, on: "1" }
    expect(response).to have_http_status(:forbidden)
    patch battle_auto_path(battle), params: { unit: bartz, on: "1" }
    expect(battle.reload.auto?(bartz)).to be(true)
    get battle_panel_path(battle)
    expect(response.body).to include("Auto is on")
  end

  it "tells a player the round, and what the clock does if they don't choose" do
    timed = start_battle(input_seconds: 30)
    me = timed.party.first.id
    sit_in_battle(timed, me)
    get battle_panel_path(timed)
    expect(response.body).to include("Round 1", "Choose before the clock runs out, or you Attack.")
    post battle_actions_path(timed), params: { command: { kind: "defend" }, actor: me }
    get battle_panel_path(timed)
    expect(response.body).not_to include("Choose before the clock runs out")
  end

  it "offers the Fight panel's monsters without a boss's later forms, which come by its phases" do
    world = battle.campaign.world
    create_monster(world, slug: "warden_cracked", name: "Warden, Cracked", boss: true)
    create_monster(world, slug: "warden", name: "Warden", boss: true, phases: [ { hp_below: 50, becomes: "warden_cracked" } ])
    battle.call_off! # the table calls Battle once the fight is over
    sit(battle.campaign, "gm")
    get new_campaign_battle_path(battle.campaign) # calls Battle at the table: the Fight panel
    follow_redirect!
    names = page.css("select[name='battle[encounter][0][monster]'] option").map(&:text)
    expect(names.join).to include("Warden (")
    expect(names.join).not_to include("Warden, Cracked")
  end

  it "says nobody fell rather than listing 0 EXP each, when they got away" do
    %w[goblin_a goblin_b].each { |id| battle.apply!({ "type" => "gm_override", "op" => "dismiss", "unit" => id }, actor: "gm") }
    sit_in_battle(battle, "gm")
    get battle_panel_path(battle)
    expect(response.body).to include("They got away before anyone fell: nothing won, nothing lost.")
    expect(response.body).not_to include("0 EXP")
  end

  it "tells a player the round ran before they chose, when the clock or the GM ran it" do
    timed = start_battle(input_seconds: 30)
    me = timed.party.first.id
    sit_in_battle(timed, me)
    timed.apply!({ "type" => "timeout" }, actor: "gm") # the clock ran out: everyone on reflex, and the next round opens
    get battle_panel_path(timed)
    expect(response.body).to include("The last round ran before you chose: you acted on reflex.")
    post battle_actions_path(timed), params: { command: { kind: "defend" }, actor: me } # chosen for this round
    get battle_panel_path(timed)
    expect(response.body).not_to include("ran before you chose")
  end

  it "warns a player at the end of their rope that an Attack may become their desperation move" do
    campaign = base_campaign
    hero = base_character(campaign, name: "Rook")
    fight = start_battle(campaign: campaign, goblins: 1)
    sit_in_battle(fight, hero.battle_unit_id)
    get battle_panel_path(fight)
    expect(response.body).not_to include("At the end of your rope")
    fight.apply!({ "type" => "gm_override", "op" => "set_hp", "unit" => hero.battle_unit_id, "value" => 10 }, actor: "gm")
    get battle_panel_path(fight)
    expect(response.body).to include("At the end of your rope:", "an Attack may become")
  end

  it "tells the GM who the round waits on, one line a unit, with one button when it matters" do
    battle.set_auto!(bartz, false)
    battle.set_auto!(faris, true)
    sit_in_battle(battle, "gm")
    get battle_panel_path(battle)
    expect(response.body).to include("Waiting on Bartz.")
    rows = page.css(".gm-rows[aria-label='The party'] .gm-row")
    expect(rows.map { |r| r.at(".gm-row__name").text }).to eq(%w[Bartz Faris])
    expect(rows[0].at(".gm-row__who").text.squish).to eq("Waiting on their player Auto") # one button: put them on auto
    expect(rows[1].at(".gm-row__who").text.squish).to eq("Auto Hand back") # one button: take them off it
    # A player who isn't with the page (the table's presence) is away, and Auto is the way on; folded controls stay as left.
    who = battle.characters_by_unit[bartz]
    who.update!(user: make_user("Bartz's player"))
    get battle_panel_path(battle)
    expect(page.css(".gm-rows[aria-label='The party'] .gm-row")[0].at(".gm-row__who").text.squish).to eq("Their player is away Auto")
    who.seen!
    get battle_panel_path(battle)
    expect(page.css(".gm-rows[aria-label='The party'] .gm-row")[0].at(".gm-row__who").text.squish).to eq("Waiting on their player Auto")
    # The words keep their own time on the page (here_controller), so away comes without a reload.
    mark = page.at(".gm-rows[aria-label='The party'] [data-here-target=who]")
    expect(mark["data-seen-at"]).to eq(who.reload.seen_at.iso8601)
    expect(mark["data-here-words"]).to eq("Waiting on their player|Their player is away")
    expect(page.at(".gm-rows[aria-label='The party']")["data-controller"]).to eq("here")
    expect(page.at("details.gm-controls")["data-controller"]).to eq("remember-open")
    expect(response.body).not_to include("Auto this round", "Auto every round", "Who chooses") # no two autos
    expect(page.at("table")).to be_nil # no table

    get battle_path(battle)
    expect(response.body).to include("Fast animations")
  end

  it "shows the GM the field the fight is on, and lets them move it on" do
    flooded = start_battle(field: { "stages" => [ { "name" => "Waist-deep", "rounds" => 4, "conditions" => [ { "kind" => "slow", "amount" => 25 } ] },
                                                  { "name" => "Chest-deep", "conditions" => [ { "kind" => "conduct", "type" => "fire" } ] } ] })
    sit_in_battle(flooded, "gm")
    get battle_panel_path(flooded)
    expect(page.text).to include("The field", "Waist-deep: everyone's Agi −25%", "rises after 4 rounds", "On to Chest-deep")

    post battle_actions_path(flooded), params: { gm: { op: "field", stage: "1" } }
    expect(flooded.reload.state.dig("field", "stage")).to eq(1)
    expect(flooded.battle_events.map(&:payload)).to include(a_hash_including("type" => "field_changed", "name" => "Chest-deep"))
    get battle_panel_path(flooded)
    expect(page.text).to include("Chest-deep: Fire hits the whole side", "Back to Waist-deep")
  end

  it "shows only the battle: overrides, reinforcements and pacing behind GM controls, Fast animations in the Menu" do
    sit_in_battle(battle, "gm")
    get battle_panel_path(battle)
    folded = page.at("details.gm-controls")
    expect(folded.text).to include("GM controls", "Someone joins", "Override", "Pacing")
    folded.remove
    expect(page.text).to include("Run the round now", "End the battle", "Call it off")
    expect(page.text).not_to include("Apply override", "Bring them in")

    get battle_path(battle)
    menu = page.at(".topbar__user-menu")
    expect(menu.text).to include("Fast animations", "Sound on", "Timing meter") # device settings, beside Sound
    expect(menu.at("[data-battle-fast]")).to be_present
    expect(menu.at("[data-timing-meter]")).to be_present
    expect(page.at("header.battle__header").text).not_to include("Fast animations")
    expect(page.css("nav.topbar__books").map(&:text).join).not_to include("Fast animations")
  end

  it "marks the hurt in the party strip, which only shows once someone is" do
    sit_in_battle(battle, bartz)
    get battle_panel_path(battle)
    expect(page.at("ol.party-strip .is-hurt, ol.party-strip .is-ko")).to be_nil
    battle.apply!({ "type" => "gm_override", "op" => "set_hp", "unit" => faris, "value" => 1 }, actor: "gm")
    get battle_panel_path(battle)
    expect(page.at("ol.party-strip .is-hurt")).to be_present
  end

  it "shows each party member's plan on the board, and what lasts on a unit with its count" do
    sit_in_battle(battle, bartz)
    command!(kind: "ability", ability: "attack", target: "goblin_a")
    get battle_path(battle)
    expect(page.css("[data-intent]").map(&:text)).to eq([ "Attack → Goblin A" ] * 2) # on the unit, and in the roster
    expect(page.at("span.intent[data-intent]")).to be_present

    sit_in_battle(battle, "gm")
    gm!(op: "add_status", unit: "goblin_a", status: "poison", turns: 3)
    get battle_path(battle)
    poison = page.at("[data-status=poison][data-turns='3']")
    expect(poison.text.squish).to eq("Poison 3")
    expect(poison.at("b").text).to eq("3")
    expect(page.at(".turn-rail")).to be_present
    expect(page.at(".round-tally")).to be_present
  end

  it "says what a move would reach, and what the party knows a target is weak to" do
    sit_in_battle(battle, bartz)
    get battle_panel_path(battle)
    expect(page.at("[data-menu-key=Attack]")["data-reach"]).to eq("single_enemy")
    expect(page.at("[data-menu-key=Cure]")["data-reach"]).to eq("single_ally")
    defend = page.at("[data-help='Halve the damage you take this round.']")
    expect(defend["data-reach"]).to eq("self")

    # The party has seen the goblin take fire: a fire-typed blow says "Weak!" before it's chosen.
    battle.campaign.update!(known_affinities: { "goblin" => { "types" => %w[normal], "fire" => "weak" } })
    knight = battle.unit(bartz)
    goblin = battle.unit("goblin_a")
    fire = battle.field.ability("fire") || BattleMove.new({ "effects" => [ { "primitive" => "elemental", "type" => "fire" } ] })
    expect(helper_edge_note(battle, knight, fire, goblin)).to eq("Weak!")
    expect(helper_edge_note(battle, knight, BattleMove.new({ "effects" => [ { "primitive" => "elemental", "type" => "water" } ] }), goblin)).to be_nil # not seen
  end

  def helper_edge_note(battle, actor, move, target)
    Class.new { include BattlesHelper, BooksHelper, ApplicationHelper }.new.edge_note(battle, battle.field, actor, move, target)
  end

  it "takes a Perfect from the timing meter with a player's move" do
    sit_in_battle(battle, bartz)
    get battle_panel_path(battle)
    expect(response.body).to include("timing-meter")
    expect(response.body).not_to include("Timing meter") # the setting is in the account menu
    command!(kind: "ability", ability: "attack", target: "goblin_a", timing: "perfect")
    expect(battle.reload.state["inputs"][bartz]).to include("timing" => "perfect")
  end

  it "lets a player try something off the menu, which the GM rules on and the dice decide" do
    sit_in_battle(battle, bartz)
    get battle_panel_path(battle)
    expect(response.body).to include("Try something")
    get battle_panel_path(battle, custom: 1)
    expect(response.body).to include("What do you try?")
    command!(kind: "custom", text: "Kick the brazier onto them", target: "goblin_a")
    expect(battle.reload.state["inputs"][bartz]).to include("kind" => "custom", "text" => "Kick the brazier onto them")

    sit_in_battle(battle, "gm")
    get battle_panel_path(battle)
    expect(response.body).to include("Ideas to rule on", "Kick the brazier onto them")
    battle.set_auto!(faris, true)
    gm!(op: "rule", unit: bartz, stat: "agi", difficulty: "easy", effect: "damage", strength: "heavy", type: "fire", aim: "all_enemies",
        success: "Coals everywhere!", failure: "It won't budge.")
    events = battle.reload.battle_events.map(&:payload)
    expect(events.map { |e| e["type"] }).to include("custom_action", "custom_roll")
    get battle_path(battle)
    expect(response.body).to include("tries: “Kick the brazier onto them”", "GM rules on Bartz&#39;s idea: Agi, easy.")
  end

  it "lets the GM rule an idea as a skill check, with the character's job bonus" do
    battle.world.jobs.find_by!(slug: "knight").update!(skills: %w[athletics])
    sit_in_battle(battle, bartz)
    command!(kind: "custom", text: "Vault the barricade")
    sit_in_battle(battle, "gm")
    get battle_panel_path(battle)
    expect(page.at("[value='skill:athletics']")).to be_present
    gm!(op: "rule", unit: bartz, stat: "skill:athletics", difficulty: "normal", effect: "none", success: "Over!", failure: "Not quite.")
    expect(battle.reload.state["inputs"][bartz]["ruling"]).to include("stat" => "str", "skill" => "Athletics", "bonus" => 15)
  end

  it "starts a battle on the terrain it's given, for the Geomancer's arts" do
    campaign = battle.campaign
    post campaign_battles_path(campaign), params: { battle: { name: "Wood", terrain: "grass", characters: [ campaign.characters.first.id ],
                                                             encounter: { "0" => { monster: "goblin", count: "1" } } } }
    expect(campaign.battles.order(:id).last.state["terrain"]).to eq("grass")
  end

  describe "setting up" do
    let!(:world) { base_world }
    let(:campaign) { base_campaign }
    let!(:bartz_character) { base_character(campaign, name: "Bartz", starting_level: 5) }
    let!(:lenna) { base_character(campaign, name: "Lenna", job: "white_mage", starting_level: 5) }

    it "starts a battle for the chosen characters and seats the creator as GM" do
      campaign.call_controls!("battle")
      at_the_table(campaign, as: "gm") # the setup is the GM's
      expect(page.at("#table_called").text).to include("Bartz", "Lenna")

      post campaign_battles_path(campaign), params: { battle: {
        name: "Ambush", seed: "42", escapable: "1", input_seconds: "60", characters: [ "", lenna.id.to_s ],
        encounter: { "0" => { monster: "goblin", count: "3" }, "1" => { monster: "", count: "1" } }
      } }
      battle = BattleRecord.last
      expect(response).to redirect_to(battle_path(battle))
      expect(battle).to have_attributes(name: "Ambush", seed: 42, input_seconds: 60, campaign: campaign)
      expect(battle.units.map(&:name)).to eq([ "Lenna", "Goblin A", "Goblin B", "Goblin C" ])

      get battle_panel_path(battle)
      expect(response.body).to include("Game Master · Round 1")
    end

    it "needs someone standing and a monster" do
      bartz_character.update!(hp: 0)
      post campaign_battles_path(campaign), params: { battle: {
        name: "Doomed", characters: [ bartz_character.id.to_s ], encounter: { "0" => { monster: "goblin", count: "1" } }
      } }
      expect(response).to redirect_to(campaign_table_path(campaign)) # back to the setup under the stage, with why
      expect(flash[:alert]).to include("still standing")

      post campaign_battles_path(campaign), params: { battle: {
        name: "Empty", characters: [ lenna.id.to_s ], encounter: { "0" => { monster: "", count: "1" } }
      } }
      expect(flash[:alert]).to include("at least one monster")
    end

    it "only uses the campaign's own characters" do
      other = world.campaigns.create!(name: "Other").characters.create!(name: "Stranger", job: world.jobs.first)
      post campaign_battles_path(campaign), params: { battle: {
        name: "X", characters: [ other.id.to_s, lenna.id.to_s ], encounter: { "0" => { monster: "goblin", count: "1" } }
      } }
      expect(BattleRecord.last.party.map(&:name)).to eq([ "Lenna" ])
    end
  end

  describe "the page" do
    it "renders the board from the current state, with a lazily loaded command panel" do
      get battle_path(battle)
      expect(response).to have_http_status(:ok)
      expect(page.at("[data-controller~=battle-player]")["data-controller"].split).to include("dialogue", "heartbeat", "recap")
      expect(page.at("turbo-cable-stream-source")).to be_present
      expect(page.at("[data-unit=goblin_a]")).to be_present
      expect(page.at("[data-roster='#{bartz}']")).to be_present
      expect(page.at("#command_panel")).to be_present
    end

    it "shows the log so far to a late joiner, without replaying anything" do
      battle.apply!({ "type" => "gm_override", "op" => "set_hp", "unit" => "goblin_a", "value" => 5, "note" => "wounded" }, actor: "gm")
      get battle_path(battle)
      expect(response.body).to include("GM sets Goblin A&#39;s HP to 5. &quot;wounded&quot;")
    end

    it "gives a boss its entrance: the name card and its line, until the fight is under way" do
      campaign = create_campaign
      plain = start_battle(campaign: campaign)
      campaign.world.monsters.find_by!(slug: "goblin").update!(boss: true, boss_line: "You dare?")
      boss_battle = start_battle(campaign: campaign)
      get battle_path(boss_battle)
      expect(page.at(".battle--boss")).to be_present
      expect(page.at("[data-boss-down]")["data-boss-down"]).to eq("Goblin falls!")
      intro = page.at("[data-controller~=boss-intro]")
      expect(intro["data-boss-intro-line-value"]).to eq("You dare?")
      expect(intro["data-boss-intro-fresh-value"]).to eq("true")

      get battle_path(plain)
      expect(page.at("[data-controller~=boss-intro], .battle--boss")).to be_nil
    end

    it "never shows enemy HP on the shared board" do
      get battle_path(battle)
      board = page.at("div.board")
      board.css("ol.roster").each(&:remove)
      expect(board.at("[data-hp]")).to be_nil
      expect(board.to_html).not_to include("data-hp")
    end
  end

  describe "seats" do
    it "offers seats until one is taken" do
      get battle_panel_path(battle)
      expect(response.body).to include("Take a seat", "Game Master", "Bartz", "Faris")

      sit_in_battle(battle, bartz)
      get battle_panel_path(battle)
      expect(page.text).to include("Seated as Bartz", "Attack", "Cure", "Defend")
      expect(page.css("strong").map(&:text)).to include("Bartz")
    end

    it "ignores seats that aren't party members" do
      sit_in_battle(battle, "goblin_a")
      get battle_panel_path(battle)
      expect(response.body).to include("Take a seat")
    end

    it "can be left" do
      sit_in_battle(battle, "gm")
      delete battle_seat_path(battle)
      follow_redirect!
      expect(response.body).to include("Take a seat")
    end
  end

  describe "players" do
    before { sit_in_battle(battle, bartz) }

    it "find their way around the campaign from the battle, their sheet included" do
      battle.campaign.characters.find_by!(name: "Bartz").update!(user: @admin)
      get battle_path(battle)
      nav = page.at("nav.topbar__books[aria-label=Campaign]")
      expect(nav.css("a").map(&:text)).to include("Table", "My sheet")
    end

    it "see who was down at the end of a win, and that they earned nothing" do
      battle.apply!({ "type" => "gm_override", "op" => "set_hp", "unit" => faris, "value" => 0 }, actor: "gm")
      battle.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "victory" }, actor: "gm")
      get battle_panel_path(battle)
      down = page.css("li, p").find { |n| n.text.include?("down at the end, so no EXP or ABP.") }
      expect(down.at("strong").text).to eq("Faris")
      expect(down.at("span.muted").text).to eq("down at the end, so no EXP or ABP.")
    end

    it "pick a target, then submit, and get a placeholder that holds no battle state" do
      get battle_panel_path(battle, ability: "attack")
      expect(page.at("[data-choosing]")).to be_present
      expect(response.body).to include("Goblin A", "Goblin B")

      command!(kind: "ability", ability: "attack", target: "goblin_b")
      expect(response).to have_http_status(:ok)
      expect(page.at("[data-resolving]")).to be_present
      expect(response.body).not_to include("Goblin", "Round", "HP")
      expect(battle.reload.state["inputs"][bartz]).to include("target" => "goblin_b")
    end

    it "get a playable menu: help for every command, the unusable ones explained, targets tied to their units" do
      state = battle.state
      state["units"].find { |u| u["id"] == bartz }["mp"] = 0
      battle.update!(state: state)

      get battle_panel_path(battle)
      menu = page.at("[data-controller~=menu]")
      expect(menu["data-controller"].split).to include("timing-meter", "battle-talk")
      expect(menu["data-menu-you-value"]).to eq(bartz)
      expect(response.body).to include("Single enemy · Physical")
      cure = page.css("[aria-disabled=true]").find { |n| n.text.strip == "Cure" }
      expect(cure["data-help"]).to start_with("Not enough MP")

      get battle_panel_path(battle, ability: "attack")
      expect(page.at("[data-unit-id=goblin_a]")).to be_present
      expect(page.at("[data-menu-back=true]")).to be_present
    end

    it "always act as their own seat, whatever the params say" do
      post battle_actions_path(battle), params: { command: { kind: "defend" }, actor: faris }
      expect(battle.reload.state["inputs"].keys).to eq([ bartz ])
      expect(battle.battle_actions.last.actor).to eq(bartz)
    end

    it "see the waiting state after submitting, and can change their command" do
      command!(kind: "defend")
      get battle_panel_path(battle)
      expect(page.text).to include("Ready: Defend", "Waiting for Faris", "Change command")
      expect(page.css("strong").map(&:text)).to include("Defend")
      get battle_panel_path(battle, change: 1)
      expect(response.body).to include("Attack")
    end

    it "get the resolver's reason when an action is illegal" do
      command!(kind: "ability", ability: "attack", target: faris)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("#{faris} is not an enemy")
    end

    it "cannot send GM overrides" do
      gm!(op: "set_hp", unit: "goblin_a", value: 0)
      expect(response).to have_http_status(:forbidden)
      expect(battle.reload.battle_actions).to be_empty
    end

    it "cannot change the playback speed" do
      patch battle_playback_path(battle), params: { speed: 4 }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "the GM" do
    it "brings in reinforcements and a guest from the Bestiary, and sends an enemy off" do
      sit_in_battle(battle, "gm")
      gm!(op: "add_unit", side: "enemy", monster: "goblin", note: "More!")
      expect(battle.reload.enemies.map(&:id)).to include("goblin_c")

      gm!(op: "add_unit", side: "party", monster: "goblin", name: "Cid")
      cid = battle.reload.unit("cid")
      expect(cid.to_h).to include("guest" => true, "name" => "Cid", "rewards" => {}, "drops" => [])
      expect(battle.party.map(&:id)).not_to include("cid")

      get battle_path(battle)
      expect(response.body).to include("roster__guest", "Cid")

      gm!(op: "dismiss", unit: "goblin_c")
      expect(battle.reload.unit("goblin_c").gone?).to be(true)
      get battle_path(battle)
      expect(page.at("[data-unit=goblin_c]")).to be_nil
      expect(response.body).to include("Goblin C leaves the field.", "GM sends Goblin C off.")
    end
    before { sit_in_battle(battle, "gm") }

    it "sees every unit's HP and who the round is waiting on" do
      get battle_panel_path(battle)
      expect(response.body).to include("The party", "Run the round now", "The other side")
      expect(page.at(".gm-rows[aria-label='The other side']").text.squish).to include("Goblin A HP 50/50")
      expect(response.body).to include("Waiting on") # by the round's clock, as well as in the rows
      expect(response.body).not_to include("On auto every round")
    end

    it "auto-pilots an absent player and runs the round, all logged" do
      gm!(op: "auto", unit: bartz)
      gm!(op: "execute_round")
      battle.reload
      expect(battle.round).to eq(2)
      expect(battle.battle_actions.map(&:actor)).to eq(%w[gm gm])
      expect(battle.battle_events.where(kind: "gm_override").count).to eq(2)
    end

    it "applies overrides with a note" do
      gm!(op: "set_hp", unit: "goblin_a", value: "7", note: "an old wound", status: "", turns: "")
      override = battle.reload.battle_events.find_by(kind: "gm_override").payload
      expect(override).to include("op" => "set_hp", "unit" => "goblin_a", "hp" => 7, "note" => "an old wound")
      expect(battle.unit("goblin_a").hp).to eq(7)

      gm!(op: "add_status", unit: "goblin_b", status: "poison", turns: "2")
      expect(battle.reload.unit("goblin_b").statuses).to eq([ { "kind" => "poison", "turns" => 2 } ])
    end

    it "ends the battle" do
      gm!(op: "end_battle", result: "fled")
      get battle_panel_path(battle)
      expect(response.body).to include("The party got away.", "replays exactly from seed 7")
    end

    it "sets the playback speed for everyone" do
      patch battle_playback_path(battle), params: { speed: 2 }
      expect(battle.reload.playback_speed).to eq(2)
    end

    it "cannot command a party member's unit" do
      command!(kind: "defend")
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "arriving" do
    let(:campaign) { create_campaign }
    let(:battle) do
      create_character(campaign, name: "Bartz", user: @admin)
      create_character(campaign, name: "Faris", user: make_user("Sam"))
      start_battle(campaign: campaign, input_seconds: 30)
    end

    it "is the player saying they're ready, never what loading the page does" do
      sit_in_battle(battle, bartz)
      get battle_path(battle)
      expect(page.at("#battle_ready")).to be_present
      expect(response.body).to include(battle_arrival_path(battle), "Ready", "is ready")
      get battle_panel_path(battle)
      expect(battle.reload.arrived_units).to be_empty

      post battle_arrival_path(battle), as: :turbo_stream
      expect(page.at("turbo-stream[action=remove]")["target"]).to eq("battle_ready")
      expect(battle.reload.arrived_units).to eq([ bartz ])
      get battle_path(battle)
      expect(page.at("#battle_ready")).to be_nil
    end

    it "counts choosing a first move as being ready" do
      sit_in_battle(battle, bartz)
      get battle_path(battle)
      expect(response.body).to include("Choosing your first move counts too.")
      post battle_actions_path(battle), params: { command: { kind: "defend" } }
      expect(battle.reload.arrived_units).to eq([ bartz ])
      get battle_panel_path(battle)
      expect(page.at("[data-chosen]")).to be_present
    end

    it "takes everyone's Ready button away once the clock runs, or the fight is over" do
      table = nil
      streams = capture_turbo_stream_broadcasts(battle) do
        table = capture_turbo_stream_broadcasts([ campaign, :table ]) do
          battle.apply!({ "type" => "gm_override", "op" => "end_battle", "result" => "victory" }, actor: "gm")
        end
      end
      expect(streams.any? { |s| s["action"] == "remove" && s["target"] == "battle_ready" }).to be(true)
      expect(table.find { |s| s["target"] == "table_battle" }.to_html).not_to include("Go to the battle") # won: the table stops pointing at it

      other = start_battle(campaign: campaign, input_seconds: 30)
      streams = capture_turbo_stream_broadcasts(other) { other.party.each { |u| other.arrive!(u.id) } }
      expect(streams.any? { |s| s["action"] == "remove" && s["target"] == "battle_ready" }).to be(true)
    end

    it "keeps the clock going while someone has the battle open, and says when it's held" do
      sit_in_battle(battle, bartz)
      get battle_path(battle)
      expect(response.body).to include("heartbeat", battle_watch_path(battle))

      patch battle_watch_path(battle)
      expect(response).to have_http_status(:no_content)
      expect(battle.reload).to be_watched

      battle.update!(arrived_units: [ bartz, faris ], deadline_at: nil) # its time ran out, unwatched
      get battle_panel_path(battle)
      expect(response.body).to include("Clock stopped: nobody had the battle open")
      patch battle_watch_path(battle)
      expect(battle.reload.deadline_at).to be_present
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The GM's moves: complications on a failed check, and what a hard move takes" do
  let(:world) { base_world }
  let(:campaign) { base_campaign(gil: 80) }
  let(:village) { world.location_templates.find_by!(slug: "village") }
  let!(:hollin) do
    campaign.map_nodes.create!(name: "Hollin", kind: "town", x: 5, y: 5, visible: true, location: campaign.locations.create!(location_template: village, seed: 3))
  end
  let!(:rook) { create_character(campaign, name: "Rook") }
  let!(:vivi) { create_character(campaign, name: "Vivi") }

  before do
    world.generator_tables.where(kind: "complications").destroy_all
    campaign.update!(current_node: hollin)
  end

  def complications(*rows)
    world.generator_tables.create!(name: "Complications", slug: "complications_#{SecureRandom.hex(2)}", kind: "complications", entries: rows)
  end

  def fail_checks!
    allow(Stats::Check).to receive(:roll).and_wrap_original { |original, **args| original.call(**args).merge("success" => false) }
  end

  def offers = campaign.messages.where(scope: "gm").select { |m| m.data["offer"] }

  describe "what a hard move takes" do
    it "takes money, as much as there is" do
      expect(Outcome.parse("lose 50").apply!(campaign, by: "The party")).to eq("The party loses 50 gil.")
      expect(Outcome.parse("lose 50").apply!(campaign, by: "The party")).to eq("The party loses 30 gil.")
      expect(campaign.reload.gil).to eq(0)
      expect(Outcome.parse("lose 50").bites?(campaign)).to be(false)
    end

    it "takes time" do
      expect { Outcome.parse("time 2").apply!(campaign, by: "The party") }.to change { campaign.reload.time_of_day }.from("dawn").to("dusk")
    end

    it "ticks the clock that matters: the one here, else the one nearest to full, and tells only the GM of a hidden one" do
      far = campaign.clocks.create!(name: "Far trouble", segments: 4, filled: 3)
      here = campaign.clocks.create!(name: "Trouble here", segments: 8, filled: 1, map_node: hollin)
      Outcome.parse("tick").apply!(campaign, by: "The party")
      expect([ here.reload.filled, far.reload.filled ]).to eq([ 2, 3 ])
      expect(campaign.messages.where(scope: "gm").pluck(:body)).to include("Trouble here: 2 of 8.")
      expect(campaign.messages.where(scope: "table").pluck(:body)).not_to include(a_string_matching(/Trouble here/))

      here.update!(stopped_at: Time.current)
      Outcome.parse("tick").apply!(campaign, by: "The party")
      expect(far.reload).to be_full
      expect(Outcome.parse("tick").bites?(campaign)).to be(false)
    end
  end

  describe "on a failed check" do
    before do
      fail_checks!
      complications({ "text" => "Something stirs." },
                    { "text" => "{who} was seen by someone who'll talk.", "when" => "skill = stealth, town", "sets" => "seen_sneaking" },
                    { "text" => "{who} pays for it.", "does" => "hurt 10" },
                    { "text" => "A purse goes missing.", "when" => "town, gil >= 20", "does" => "lose 50" },
                    { "text" => "It gets worse.", "does" => "tick" })
    end

    it "offers the GM the soft move and the hard move that fit best, and makes neither for them" do
      campaign.check!(characters: [ rook, vivi ], stat: "skill:stealth", difficulty: "normal")
      expect(offers.map(&:body)).to eq([ "A soft move, for the failed check: “Rook and Vivi was seen by someone who'll talk.”",
                                         "A hard move, for the failed check: “A purse goes missing.” (The party loses 50 gil)" ])
      expect(campaign.reload.gil).to eq(80)
      expect(campaign.flags).to be_empty
    end

    it "makes a hard move so when the GM says: its words to the table, then what it takes" do
      campaign.check!(characters: [ rook ], stat: "str", difficulty: "normal")
      soft, hard = offers
      expect(soft.body).to end_with("“Something stirs.”") # no skill, so the stealth row doesn't fit
      campaign.say_offer!(hard)
      expect(campaign.messages.where(scope: "table").last(2).map(&:body)).to eq([ "A purse goes missing.", "The party loses 50 gil." ])
      expect(campaign.reload.gil).to eq(30)
      expect { campaign.say_offer!(hard.reload) }.to raise_error(Refusal, "Already said.")
    end

    it "offers no hard move that would take nothing, and nothing at all when the check is made" do
      campaign.update!(gil: 0)
      campaign.check!(characters: [ rook ], stat: "str", difficulty: "normal")
      expect(offers.last.body).to eq("A hard move, for the failed check: “Rook pays for it.” (Everyone standing loses 10% of HP)")

      RSpec::Mocks.space.proxy_for(Stats::Check).reset
      allow(Stats::Check).to receive(:roll).and_wrap_original { |original, **args| original.call(**args).merge("success" => true) }
      expect { campaign.check!(characters: [ rook ], stat: "str", difficulty: "easy") }.not_to(change { offers.size })
    end
  end

  it "won't take a row whose hard move isn't one" do
    table = world.generator_tables.new(name: "Bad", slug: "bad_complications", kind: "complications",
                                       entries: [ { "text" => "Lucky!", "does" => "money 40" } ])
    expect(table).not_to be_valid
    expect(table.errors.full_messages.to_sentence).to include("“money 40” isn't something a hard move takes")
  end
end

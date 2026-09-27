# frozen_string_literal: true

RSpec.describe Battle::State do
  describe ".build" do
    subject(:state) { build_battle(seed: 77) }

    it "produces a JSON-stable hash" do
      expect(described_class.normalize(state)).to eq(state)
    end

    it "starts in the input phase at round 1 with seeded RNG" do
      expect(state).to include("version" => 1, "seed" => 77, "rng" => 77, "round" => 1,
                               "status" => "input", "inputs" => {}, "escapable" => true)
    end

    it "adds the built-in Attack to the library and every unit" do
      expect(state["abilities"]["attack"]).to include("kind" => "attack", "target" => "single_enemy")
      expect(state["units"]).to all(include("abilities" => include("attack")))
    end

    it "expands enemy counts into lettered instances" do
      enemies = state["units"].select { |u| u["side"] == "enemy" }
      expect(enemies.map { |u| u["id"] }).to eq(%w[goblin_a goblin_b goblin_c])
      expect(enemies.map { |u| u["name"] }).to eq([ "Goblin A", "Goblin B", "Goblin C" ])
    end

    it "does not letter a lone enemy" do
      state = build_battle(enemies: BattleFixtures.ogre)
      expect(unit(state, "ogre")["name"]).to eq("Ogre")
    end

    it "starts units at full HP/MP unless told otherwise" do
      party = BattleFixtures.party
      party[0] = party[0].merge(hp: 50, mp: 999)
      state = build_battle(party: party)
      expect(unit(state, "bartz")).to include("hp" => 50, "mp" => 20)
      expect(unit(state, "vivi")).to include("hp" => 70, "mp" => 40)
    end

    it "rejects duplicate ids" do
      party = BattleFixtures.party + [ BattleFixtures.party.first ]
      expect { build_battle(party: party) }.to raise_error(ArgumentError, /duplicate/)
    end

    it "rejects units that know abilities missing from the library" do
      party = [ { id: "x", stats: stats, abilities: [ "ultima" ] } ]
      expect { build_battle(party: party) }.to raise_error(ArgumentError, /ultima/)
    end

    it "rejects units missing stats" do
      expect { build_battle(party: [ { id: "x", stats: { max_hp: 10 } } ]) }.to raise_error(ArgumentError, /missing stats/)
    end

    it "rejects unknown types and affinities, and more than two types" do
      expect { build_battle(party: [ { id: "x", stats: stats, affinities: { fire: "loves" } } ]) }.to raise_error(ArgumentError, /affinities/)
      expect { build_battle(party: [ { id: "x", stats: stats, affinities: { holy: "weak" } } ]) }.to raise_error(ArgumentError, /affinities/)
      expect { build_battle(party: [ { id: "x", stats: stats, types: %w[fairy] } ]) }.to raise_error(ArgumentError, /unknown types/)
      expect { build_battle(party: [ { id: "x", stats: stats, types: %w[fire water ice] } ]) }.to raise_error(ArgumentError, /two types/)
    end

    describe "closed vocabularies" do
      def build_with(ability)
        build_battle(abilities: { custom: ability })
      end

      it "rejects unknown primitives" do
        ability = { kind: "magic", target: "single_enemy", effects: [ { primitive: "gravity" } ] }
        expect { build_with(ability) }.to raise_error(ArgumentError, /primitive gravity/)
      end

      it "rejects unknown targeting" do
        ability = { kind: "magic", target: "everyone", effects: [ { primitive: "heal", power: 1 } ] }
        expect { build_with(ability) }.to raise_error(ArgumentError, /targeting/)
      end

      it "rejects unknown types, statuses and buff stats" do
        expect { build_with(kind: "magic", target: "self", effects: [ { primitive: "elemental", type: "fairy", power: 1 } ]) }
          .to raise_error(ArgumentError, /unknown type fairy/)
        expect { build_with(kind: "skill", target: "self", effects: [ { primitive: "physical", type: "dragon" } ]) }
          .to raise_error(ArgumentError, /unknown type dragon/)
        expect { build_with(kind: "magic", target: "self", effects: [ { primitive: "status", kind: "zombie" } ]) }
          .to raise_error(ArgumentError, /status/)
        expect { build_with(kind: "magic", target: "self", effects: [ { primitive: "buff", stat: "max_hp", amount: 1 } ]) }
          .to raise_error(ArgumentError, /max_hp/)
      end

      it "rejects missing, unknown and non-integer primitive params" do
        expect { build_with(kind: "magic", target: "self", effects: [ { primitive: "heal" } ]) }
          .to raise_error(ArgumentError, /heal needs power/)
        expect { build_with(kind: "magic", target: "self", effects: [ { primitive: "heal", power: 5, type: "fire" } ]) }
          .to raise_error(ArgumentError, /does not take type/)
        expect { build_with(kind: "magic", target: "self", effects: [ { primitive: "heal", power: "5" } ]) }
          .to raise_error(ArgumentError, /must be an integer/)
      end

      it "rejects abilities with no effects" do
        expect { build_with(kind: "skill", target: "self", effects: []) }.to raise_error(ArgumentError, /effect/)
      end
    end
  end

  describe "UI queries" do
    let(:state) { Battle::State.normalize(build_battle) }

    it "lists who can act and who the round is waiting on" do
      unit(state, "vivi")["hp"] = 0
      unit(state, "rosa")["statuses"] << { "kind" => "sleep", "turns" => 2 }
      state["inputs"]["bartz"] = { "kind" => "defend" }
      expect(described_class.able_to_act(state)).to eq(%w[bartz locke])
      expect(described_class.awaiting_input(state)).to eq(%w[locke])
      expect(described_class.awaiting_input(state.merge("status" => "victory"))).to eq([])
    end

    it "matches the resolver on what counts as a legal target" do
      unit(state, "bartz")["hp"] = 0
      rosa = unit(state, "rosa")
      expect(described_class.target_options(state, rosa, state["abilities"]["cure"])).to eq(%w[vivi rosa locke goblin_a goblin_b goblin_c])
      expect(described_class.target_options(state, rosa, state["abilities"]["raise"])).to eq(%w[bartz])
      expect(described_class.target_options(state, rosa, state["abilities"]["attack"])).to eq(%w[goblin_a goblin_b goblin_c])
      expect(described_class.target_options(state, rosa, state["abilities"]["cura"])).to be_nil

      # every offered target is accepted by the resolver
      %w[cure raise attack].each do |ability|
        described_class.target_options(state, rosa, state["abilities"][ability]).each do |target|
          expect { Battle::Resolver.apply(state, command("rosa", ability, target)) }.not_to raise_error
        end
      end
    end

    it "knows when an ability is usable" do
      vivi = unit(state, "vivi")
      fire = state["abilities"]["fire"]
      expect(described_class.usable?(vivi, fire)).to be(true)
      expect(described_class.usable?(vivi.merge("mp" => 3), fire)).to be(false)
      expect(described_class.usable?(vivi.merge("statuses" => [ { "kind" => "silence", "turns" => 1 } ]), fire)).to be(false)
      expect(described_class.usable?(unit(state, "bartz"), fire)).to be(false)
    end
  end
end

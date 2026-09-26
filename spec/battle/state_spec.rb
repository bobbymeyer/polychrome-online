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

    it "rejects unknown elements and affinities" do
      party = [ { id: "x", stats: stats, elements: { fire: "loves" } } ]
      expect { build_battle(party: party) }.to raise_error(ArgumentError, /elements/)
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

      it "rejects unknown elements, statuses and buff stats" do
        expect { build_with(kind: "magic", target: "self", effects: [ { primitive: "elemental", element: "poison", power: 1 } ]) }
          .to raise_error(ArgumentError, /element/)
        expect { build_with(kind: "magic", target: "self", effects: [ { primitive: "status", kind: "zombie" } ]) }
          .to raise_error(ArgumentError, /status/)
        expect { build_with(kind: "magic", target: "self", effects: [ { primitive: "buff", stat: "max_hp", amount: 1 } ]) }
          .to raise_error(ArgumentError, /max_hp/)
      end

      it "rejects missing, unknown and non-integer primitive params" do
        expect { build_with(kind: "magic", target: "self", effects: [ { primitive: "heal" } ]) }
          .to raise_error(ArgumentError, /heal needs power/)
        expect { build_with(kind: "magic", target: "self", effects: [ { primitive: "heal", power: 5, element: "fire" } ]) }
          .to raise_error(ArgumentError, /does not take element/)
        expect { build_with(kind: "magic", target: "self", effects: [ { primitive: "heal", power: "5" } ]) }
          .to raise_error(ArgumentError, /must be an integer/)
      end

      it "rejects abilities with no effects" do
        expect { build_with(kind: "skill", target: "self", effects: []) }.to raise_error(ArgumentError, /effect/)
      end
    end
  end
end

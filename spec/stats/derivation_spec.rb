# frozen_string_literal: true

RSpec.describe Stats::Derivation do
  let(:base) do
    { "max_hp" => 200, "max_mp" => 30, "str" => 20, "mag" => 10, "vit" => 15,
      "spr" => 12, "agi" => 16, "atk" => 0, "def" => 0, "mdef" => 0 }
  end

  describe ".derive" do
    it "returns every stat, defaulting missing ones to their floor" do
      derived = described_class.derive(base: { "str" => 5 })
      expect(derived.keys).to eq(Stats::NAMES)
      expect(derived["max_hp"]).to eq(1)
      expect(derived["agi"]).to eq(0)
    end

    it "passes base stats through untouched with no modifiers" do
      expect(described_class.derive(base: base)).to eq(base)
    end

    it "accepts symbol keys" do
      expect(described_class.derive(base: base.transform_keys(&:to_sym))).to eq(base)
    end

    it "applies job multipliers as percentages, flooring" do
      derived = described_class.derive(base: base, job: { "multipliers" => { "str" => 125, "mag" => 55 } })
      expect(derived["str"]).to eq(25)
      expect(derived["mag"]).to eq(5) # 10 * 0.55 = 5.5 -> 5
      expect(derived["vit"]).to eq(15)
    end

    it "adds equipment after the job multiplier" do
      derived = described_class.derive(
        base: base,
        job: { multipliers: { atk: 200 } },
        equipment: [{ stats: { atk: 12, def: 3 } }, { "stats" => { "def" => 4 } }]
      )
      expect(derived["atk"]).to eq(12) # job multiplies base 0, not the weapon
      expect(derived["def"]).to eq(7)
    end

    it "applies passive additions before passive percentages" do
      derived = described_class.derive(
        base: base,
        equipment: [{ stats: { str: 10 } }],
        passives: [{ stat: "str", add: 10 }, { stat: "str", percent: 50 }, { stat: "agi", percent: -25 }]
      )
      expect(derived["str"]).to eq((20 + 10 + 10) * 150 / 100)
      expect(derived["agi"]).to eq(12)
    end

    it "clamps to caps" do
      derived = described_class.derive(
        base: base.merge("max_hp" => 9000, "str" => 250),
        passives: [{ stat: "max_hp", percent: 50 }, { stat: "str", add: 100 }]
      )
      expect(derived["max_hp"]).to eq(9999)
      expect(derived["str"]).to eq(255)
    end

    it "never lets a penalty push a stat below its floor" do
      derived = described_class.derive(base: base, passives: [{ stat: "max_hp", add: -500 }, { stat: "agi", add: -99 }])
      expect(derived["max_hp"]).to eq(1)
      expect(derived["agi"]).to eq(0)
    end

    it "rejects unknown stats" do
      expect { described_class.derive(base: { "luck" => 3 }) }.to raise_error(ArgumentError, /luck/)
    end

    it "is pure" do
      frozen = base.freeze
      equipment = [{ "stats" => { "atk" => 5 }.freeze }.freeze].freeze
      expect { described_class.derive(base: frozen, equipment: equipment) }.not_to raise_error
      expect(described_class.derive(base: base, equipment: equipment))
        .to eq(described_class.derive(base: base, equipment: equipment))
    end

    it "keeps every stat within [floor, cap] for arbitrary inputs" do
      rng = Random.new(7)
      500.times do
        b = Stats::NAMES.to_h { |n| [n, rng.rand(0..400)] }
        job = { "multipliers" => Stats::NAMES.to_h { |n| [n, rng.rand(0..300)] } }
        equip = Array.new(rng.rand(0..3)) { { "stats" => { Stats::NAMES.sample(random: rng) => rng.rand(-50..200) } } }
        passives = Array.new(rng.rand(0..3)) do
          { "stat" => Stats::NAMES.sample(random: rng), rng.rand(2).zero? ? "add" : "percent" => rng.rand(-100..100) }
        end

        described_class.derive(base: b, job: job, equipment: equip, passives: passives).each do |name, value|
          floor = name == "max_hp" ? 1 : 0
          expect(value).to be_between(floor, Stats::CAPS[name]), "#{name}=#{value}"
          expect(value).to be_a(Integer)
        end
      end
    end
  end

  describe ".effective" do
    let(:derived) { described_class.derive(base: base) }

    it "is the identity without buffs or statuses" do
      expect(described_class.effective(derived)).to eq(derived)
    end

    it "applies buffs and debuffs as percentages" do
      result = described_class.effective(derived, buffs: [
                                           { "stat" => "str", "amount" => 50, "turns" => 2 },
                                           { "stat" => "agi", "amount" => -25, "turns" => 2 }
                                         ])
      expect(result["str"]).to eq(30)
      expect(result["agi"]).to eq(12)
    end

    it "stacks buffs additively" do
      result = described_class.effective(derived, buffs: [{ stat: "str", amount: 50 }, { stat: "str", amount: -20 }])
      expect(result["str"]).to eq(26)
    end

    it "applies stat-altering statuses" do
      expect(described_class.effective(derived, statuses: ["haste"])["agi"]).to eq(24)
      expect(described_class.effective(derived, statuses: ["slow"])["agi"]).to eq(8)
      expect(described_class.effective(derived, statuses: %w[haste slow])["agi"]).to eq(16)
      expect(described_class.effective(derived, statuses: ["poison"])).to eq(derived)
    end

    it "clamps the combined modifier" do
      huge = described_class.effective(derived, buffs: Array.new(5) { { stat: "str", amount: 100 } })
      tiny = described_class.effective(derived, buffs: Array.new(5) { { stat: "str", amount: -100 } })
      expect(huge["str"]).to eq(60) # +200% ceiling
      expect(tiny["str"]).to eq(2)  # -90% floor
    end

    it "never modifies HP/MP pools" do
      result = described_class.effective(derived, buffs: [{ stat: "max_hp", amount: 100 }])
      expect(result["max_hp"]).to eq(200)
    end
  end
end

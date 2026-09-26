# frozen_string_literal: true

RSpec.describe Stats::Growth do
  describe "levels" do
    it "needs no EXP for level 1 and more for every level after" do
      expect(described_class.exp_for_level(1)).to eq(0)
      thresholds = (1..99).map { |l| described_class.exp_for_level(l) }
      expect(thresholds.each_cons(2).map { |a, b| b - a }).to all(be > 0)
    end

    it "inverts exp_for_level exactly at every threshold" do
      (1..99).each do |level|
        exp = described_class.exp_for_level(level)
        expect(described_class.level_for_exp(exp)).to eq(level)
        expect(described_class.level_for_exp(exp - 1)).to eq(level - 1) if level > 1
      end
    end

    it "caps at level 99" do
      expect(described_class.level_for_exp(10**9)).to eq(99)
      expect(described_class.exp_for_level(150)).to eq(described_class.exp_for_level(99))
    end
  end

  describe ".base_stats" do
    it "gives a fresh adventurer's numbers at level 5" do
      expect(described_class.base_stats(5)).to include("max_hp" => 150, "max_mp" => 30, "str" => 12, "agi" => 12, "atk" => 0)
    end

    it "never decreases with level and stays within the derivation caps" do
      (1..98).each do |level|
        now = described_class.base_stats(level)
        after = described_class.base_stats(level + 1)
        expect(now.keys).to eq(Stats::NAMES)
        Stats::NAMES.each { |name| expect(after[name]).to be >= now[name] }
      end
      top = described_class.base_stats(99)
      expect(Stats::Derivation.derive(base: top)).to eq(top) # nothing clipped by caps
    end
  end

  describe "job levels" do
    let(:costs) { [ 10, 10, 20, 40 ] }

    it "counts the learn-table rows the ABP covers" do
      expect([ 0, 9, 10, 19, 20, 39, 40, 79, 80, 500 ].map { |abp| described_class.job_level(abp, costs) })
        .to eq([ 0, 0, 1, 1, 2, 2, 3, 3, 4, 4 ])
    end

    it "round-trips with abp_for_job_level" do
      (0..costs.size).each do |level|
        expect(described_class.job_level(described_class.abp_for_job_level(level, costs), costs)).to eq(level)
      end
      expect(described_class.abp_for_job_level(9, costs)).to eq(80)
    end

    it "handles jobs with no learn table" do
      expect(described_class.job_level(100, [])).to eq(0)
    end

    it "treats free rows as learned at once" do
      expect(described_class.job_level(0, [ 0, 0, 5 ])).to eq(2)
    end
  end
end

# frozen_string_literal: true

RSpec.describe Battle::Rng do
  it "produces the same stream for the same seed" do
    a = described_class.new(99)
    b = described_class.new(99)
    expect(Array.new(50) { a.int(1000) }).to eq(Array.new(50) { b.int(1000) })
  end

  it "produces different streams for different seeds" do
    a = described_class.new(1)
    b = described_class.new(2)
    expect(Array.new(10) { a.next_u32 }).not_to eq(Array.new(10) { b.next_u32 })
  end

  it "resumes exactly from its exposed state" do
    rng = described_class.new(1234)
    5.times { rng.next_u32 }
    resumed = described_class.new(rng.state)
    expect(Array.new(20) { resumed.next_u32 }).to eq(Array.new(20) { rng.next_u32 })
  end

  it "keeps its state within 32 bits" do
    rng = described_class.new(2**40 + 17)
    1000.times do
      rng.next_u32
      expect(rng.state).to be_between(0, 0xFFFF_FFFF)
    end
  end

  it "returns ints in range and covers the range" do
    rng = described_class.new(5)
    values = Array.new(2000) { rng.int(6) }
    expect(values.uniq.sort).to eq((0..5).to_a)
  end

  it "is roughly uniform" do
    rng = described_class.new(11)
    counts = Array.new(10_000) { rng.int(4) }.tally
    counts.each_value { |n| expect(n).to be_within(250).of(2500) }
  end

  it "rejects non-positive ranges" do
    expect { described_class.new(1).int(0) }.to raise_error(ArgumentError)
  end

  it "picks nil from an empty array" do
    expect(described_class.new(1).pick([])).to be_nil
  end
end

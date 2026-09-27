# frozen_string_literal: true

RSpec.describe Stats::Mastery do
  it "masters an ability 40 job levels after it's learned, and everything by job level 100" do
    expect(described_class.mastered_at(1)).to eq(41)
    expect(described_class.mastered_at(60)).to eq(100)
    expect(described_class.mastered_at(80)).to eq(100)
    expect(described_class.mastered_at(100)).to eq(100)
  end

  it "grows from 0 to 100 percent on the way" do
    expect([ 9, 10, 30, 49, 50, 90 ].map { |level| described_class.percent(level, 10) }).to eq([ nil, 0, 50, 97, 100, 100 ])
    expect(described_class.percent(100, 100)).to eq(100)
    expect(described_class).to be_mastered(50, 10)
    expect(described_class).not_to be_mastered(49, 10)
  end

  it "keeps a master who has moved on ahead of a beginner in the job" do
    beginner = described_class.power(0, active: true)
    moved_on = described_class.power(100, active: false)
    expect([ beginner, moved_on, described_class.power(100, active: true) ]).to eq([ 125, 150, 175 ])
    expect(moved_on).to be > beginner
  end
end

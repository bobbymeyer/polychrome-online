# frozen_string_literal: true

require "rails_helper"

RSpec.describe Portrait do
  let(:campaign) { create_campaign }
  let(:cid) { campaign.npcs.create!(name: "Cid") }
  let(:image) { Rack::Test::UploadedFile.new(file_fixture("goblin.png"), "image/png") }

  it "falls back to neutral, then nothing" do
    expect(cid.portrait_image("angry")).to be_nil
    cid.update_portraits!(uploads: { "neutral" => image })
    expect(cid.portrait_image("angry").blob).to eq(cid.portraits.find_by!(expression: "neutral").image.blob)
    cid.update_portraits!(uploads: { "angry" => Rack::Test::UploadedFile.new(file_fixture("goblin.png"), "image/png") })
    expect(cid.portrait_image("angry").blob).to eq(cid.portraits.find_by!(expression: "angry").image.blob)
  end

  it "falls back to the job's image for a character" do
    bartz = create_character(campaign)
    expect(bartz.portrait_image("happy")).to be_nil
    bartz.job.image.attach(image)
    expect(bartz.reload.portrait_image("happy").blob).to eq(bartz.job.image.blob)
  end

  it "stands a speaker on the stage as their sprite, uploaded or removed with the portraits; a character as their archetype's figure" do
    expect(cid.sprite_image).to be_nil
    cid.update_portraits!(sprite_upload: image)
    expect(cid.sprite_image.blob).to eq(cid.sprite.image.blob)
    cid.update_portraits!(remove_sprite: true)
    expect(cid.reload.sprite).to be_nil

    bartz = create_character(campaign)
    expect(bartz.sprite_image).to be_nil
    bartz.job.image.attach(image)
    expect(bartz.reload.sprite_image.blob).to eq(bartz.job.image.blob)
    bartz.update_portraits!(sprite_upload: Rack::Test::UploadedFile.new(file_fixture("goblin.png"), "image/png"))
    expect(bartz.reload.sprite_image.blob).to eq(bartz.sprite.image.blob)
  end

  it "removes portraits and ignores unknown expressions" do
    cid.update_portraits!(uploads: { "sad" => image })
    cid.update_portraits!(removals: [ "sad" ])
    expect(cid.portraits.reload).to be_empty
    expect { cid.update_portraits!(uploads: { "smug" => image }) }.to raise_error(ActiveRecord::RecordInvalid)
  end
end

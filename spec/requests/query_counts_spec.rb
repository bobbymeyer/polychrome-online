# frozen_string_literal: true

require "rails_helper"

# The table and the GM's pages render everything a campaign has. What they
# ask the database shouldn't grow with it: a page that runs one more query
# for every place on the map is fine with three places and crawls with
# thirty. Each page is rendered with a small campaign and a bigger one, and
# must ask the same number of questions of both.
RSpec.describe "Queries per page", type: :request do
  let(:world) { base_world }
  let(:campaign) { world.campaigns.create!(name: "Crystal Road", gm: @admin) }

  def add_places(count)
    village = world.location_templates.find_by!(slug: "village")
    cave = world.location_templates.find_by!(slug: "goblin_cave")
    count.times do |i|
      template = i.even? ? village : cave
      location = campaign.locations.create!(location_template: template, seed: 100 + i)
      node = campaign.map_nodes.create!(name: "Place #{campaign.map_nodes.count}", kind: template.kind, x: i * 10, y: i * 10, visible: true, location: location)
      mode = location.map_node.modes.create!(name: "Under siege #{i}", line: "Smoke.")
      campaign.clocks.create!(name: "Clock #{node.id}", segments: 4, public: i.odd?, mode: mode)
      npc = campaign.npcs.create!(name: "Npc #{node.id}", location: location)
      campaign.secrets.create!(body: "Secret #{node.id}", location: location, npc: npc)
      create_character(campaign, name: "Hero #{node.id}", job: world.jobs.first) if i < 2
      campaign.rumours.create!(body: "Rumour #{node.id}", origin: node)
    end
    campaign.update!(current_node: campaign.map_nodes.first)
  end

  # Queries the page runs (not the ones Rails answers from its cache, unless
  # asked: cached ones still mean code asking again for what it has).
  # SHOW_QUERIES=1 prints the lines whose queries grew, to find the culprit.
  def queries_for(path, cached: false)
    get path # warm up: the first render also loads caches
    count = 0
    counter = lambda do |*, payload|
      next if payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) || (payload[:cached] && !cached)

      count += 1
      @sites[[ @phase, path, where_from(caller) ]] += 1 if ENV["SHOW_QUERIES"]
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get path }
    expect(response).to have_http_status(:ok)
    count
  end

  def where_from(stack)
    [ stack.find { |l| l.include?("/app/") }, stack.find { |l| l.include?("/app/views") } ].compact.uniq
      .map { |l| l.sub(Rails.root.to_s, "").sub(/:in .*/, "") }.join(" < ")
  end

  def counts(pages) = pages.to_h { |name, path| [ name, queries_for(path.call) ] }

  it "asks the same questions however many places there are" do
    pages = { table: -> { campaign_table_path(campaign) }, prep: -> { campaign_prep_path(campaign) },
              campaign: -> { campaign_path(campaign) }, map: -> { campaign_maps_path(campaign) },
              legends: -> { campaign_legends_path(campaign) } }
    @sites = Hash.new(0)
    add_places(2)
    @phase = :small
    small = counts(pages)
    add_places(4)
    @phase = :big
    big = counts(pages)
    if ENV["SHOW_QUERIES"]
      puts "QUERIES small=#{small} big=#{big}"
      @sites.each { |(phase, path, site), n| puts "+#{n - @sites[[ :small, path, site ]]} #{path} #{site}" if phase == :big && n > @sites[[ :small, path, site ]] }
    end
    expect(big).to eq(small)
  end

  # A scene on the stage: its step's stage is folded from every step before
  # it (Scene#stage_at), and each sprite step names someone from the cast.
  # However many sprite steps the fold runs through, the table asks for the
  # cast once (counting the questions the query cache answers, too: asking
  # again for each step is the waste).
  def stage_scene_with(sprite_steps)
    cast = [ campaign.npcs.find_or_create_by!(name: "Cid"), campaign.npcs.find_or_create_by!(name: "Faris") ]
    scene = campaign.scenes.create!(name: "Steps #{sprite_steps}")
    sprite_steps.times do |i|
      figure = { type: "Npc", id: cast[i % 2].id, side: (i.even? ? "left" : "right"), expression: Portrait::EXPRESSIONS[i % Portrait::EXPRESSIONS.size] }
      scene.beats.create!(kind: "sprite", action: (i < 2 ? "enter" : "change"), figures: [ figure ])
    end
    scene.beats.create!(text: "Here we are.")
    scene.start!
    scene
  end

  it "asks for the cast once however many sprite steps the staged scene has" do
    @sites = Hash.new(0)
    path = campaign_table_path(campaign)
    few = stage_scene_with(2)
    @phase = :small
    small = queries_for(path, cached: true)
    few.stop!
    stage_scene_with(8)
    @phase = :big
    big = queries_for(path, cached: true)
    if ENV["SHOW_QUERIES"]
      puts "QUERIES small=#{small} big=#{big}"
      @sites.each { |(phase, p, site), n| puts "+#{n - @sites[[ :small, p, site ]]} #{p} #{site}" if phase == :big && n > @sites[[ :small, p, site ]] }
    end
    expect(big).to eq(small)
  end
end

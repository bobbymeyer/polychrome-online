# frozen_string_literal: true

# Campaigns written ahead of time (db/seeds/campaigns/<slug>.rb, each a
# Seeds module), started for a GM.
namespace :campaigns do
  desc "Start a written campaign for a GM, by their email (campaigns:seed[just_seven,gm@example.com])"
  task :seed, [ :slug, :gm ] => :environment do |_, args|
    gm = args[:gm].presence && User.find_by!(email_address: args[:gm].strip.downcase)
    campaign = Seeds.campaign(args.fetch(:slug)).run(gm: gm)
    puts "#{campaign.name} is ready in #{campaign.world.name}#{" for #{gm.email_address}" if gm}: " \
         "#{campaign.map_nodes.count} places, #{campaign.npcs.count} people, #{campaign.scenes.count} scenes, " \
         "#{campaign.secrets.count} secrets. Invite code #{campaign.join_code}."
  end

  desc "Export a campaign's prep as a module (campaigns:export[12,tmp/the-just-seven.module.zip])"
  task :export, [ :id, :path ] => :environment do |_, args|
    campaign = Campaign.find(args.fetch(:id))
    export = CampaignModule::Export.new(campaign)
    path = args[:path].presence || export.filename
    File.binwrite(path, export.to_zip)
    puts "Wrote #{campaign.name} to #{path}."
  end

  desc "Start a campaign from a module file, in a world, for a GM (campaigns:import[oda,tmp/the-just-seven.module.zip,gm@example.com])"
  task :import, [ :world, :path, :gm ] => :environment do |_, args|
    world = World.find_by!(slug: args.fetch(:world))
    gm = args[:gm].presence && User.find_by!(email_address: args[:gm].strip.downcase)
    campaign = File.open(args.fetch(:path), "rb") { |file| CampaignModule::Import.new(file, world: world, gm: gm).run! }
    puts "#{campaign.name} is ready in #{world.name}: #{campaign.map_nodes.count} places, #{campaign.npcs.count} people, " \
         "#{campaign.scenes.count} scenes. Invite code #{campaign.join_code}."
  rescue Refusal => e
    abort e.message
  end
end

module Seeds
  # The campaign module for a slug: "just_seven" is Seeds::JustSeven in db/seeds/campaigns/just_seven.rb.
  def self.campaign(slug)
    slug = slug.to_s.downcase
    raise ArgumentError, "No campaign at db/seeds/campaigns/#{slug}.rb" unless Rails.root.join("db/seeds/campaigns/#{slug}.rb").exist?

    require Rails.root.join("db/seeds/campaigns/#{slug}")
    const_get(slug.camelize)
  end
end

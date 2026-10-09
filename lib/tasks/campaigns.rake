# frozen_string_literal: true

# Campaigns written ahead of time (db/seeds/campaigns/<slug>.rb, each a
# Seeds module), started for a GM.
namespace :campaigns do
  desc "Start a written campaign for a GM, by their email (campaigns:seed[dead_calm,gm@example.com])"
  task :seed, [ :slug, :gm ] => :environment do |_, args|
    gm = args[:gm].presence && User.find_by!(email_address: args[:gm].strip.downcase)
    campaign = Seeds.campaign(args.fetch(:slug)).run(gm: gm)
    puts "#{campaign.name} is ready in #{campaign.world.name}#{" for #{gm.email_address}" if gm}: " \
         "#{campaign.map_nodes.count} places, #{campaign.npcs.count} people, #{campaign.scenes.count} scenes, " \
         "#{campaign.secrets.count} secrets. Invite code #{campaign.join_code}."
  end
end

module Seeds
  # The campaign module for a slug: "dead_calm" is Seeds::DeadCalm in db/seeds/campaigns/dead_calm.rb.
  def self.campaign(slug)
    slug = slug.to_s.downcase
    raise ArgumentError, "No campaign at db/seeds/campaigns/#{slug}.rb" unless Rails.root.join("db/seeds/campaigns/#{slug}.rb").exist?

    require Rails.root.join("db/seeds/campaigns/#{slug}")
    const_get(slug.camelize)
  end
end

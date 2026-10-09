# frozen_string_literal: true

# The seeded settings besides the Base World (db/seeds/<slug>.rb, each a
# Seeds module). db:seed adds every one of them; these take one at a time.
namespace :worlds do
  desc "Seed one setting from db/seeds/<slug>.rb, adding only what's missing (worlds:seed[greenware])"
  task :seed, [ :slug ] => :environment do |_, args|
    world = Seeds.world(args.fetch(:slug)).run
    puts "Seeded #{world.name}: #{world.abilities.count} abilities, #{world.items.count} items, #{world.jobs.count} archetypes, " \
         "#{world.monsters.count} monsters, #{world.world_places.count} places, #{world.codex_entries.count} codex pages"
  end

  desc "Put every entry of one seeded setting back to its seed data, overwriting edits (worlds:update[greenware])"
  task :update, [ :slug ] => :environment do |_, args|
    world = Seeds.world(args.fetch(:slug)).run(overwrite: true)
    puts "Updated #{world.name} from the seed data: every entry is back to what db/seeds/#{args[:slug]}/ says."
  end

  desc "Export a whole world as a package (worlds:export[oda,tmp/oda.world.zip])"
  task :export, [ :slug, :path ] => :environment do |_, args|
    world = World.find_by!(slug: args.fetch(:slug))
    export = WorldPackage::Export.new(world)
    path = args[:path].presence || export.filename
    File.binwrite(path, export.to_zip)
    puts "Wrote #{world.name} to #{path}."
  end

  desc "Make a new world from a package, for an owner (worlds:import[tmp/oda.world.zip,author@example.com,oda_copy])"
  task :import, [ :path, :owner, :slug ] => :environment do |_, args|
    owner = args[:owner].presence && User.find_by!(email_address: args[:owner].strip.downcase)
    world = File.open(args.fetch(:path), "rb") { |file| WorldPackage::Import.new(file, owner: owner, slug: args[:slug]).run! }
    puts "Imported #{world.name} as #{world.slug}: #{world.abilities.count} abilities, #{world.items.count} items, " \
         "#{world.jobs.count} archetypes, #{world.monsters.count} monsters, #{world.world_places.count} places."
  rescue Refusal => e
    abort e.message
  end
end

module Seeds
  # The seed module for a slug: "greenware" is Seeds::Greenware in db/seeds/greenware.rb.
  def self.world(slug)
    slug = slug.to_s.downcase
    raise ArgumentError, "No seed at db/seeds/#{slug}.rb" unless Rails.root.join("db/seeds/#{slug}.rb").exist?

    require Rails.root.join("db/seeds/#{slug}")
    const_get(slug.camelize)
  end
end

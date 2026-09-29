# frozen_string_literal: true

namespace :base_world do
  desc "Put every Base World entry back to the seed data, overwriting edits (db:seed only adds what's missing)"
  task update: :environment do
    require Rails.root.join("db/seeds/base_world")
    world = Seeds::BaseWorld.run(overwrite: true)
    puts "Updated #{world.name} from the seed data: every entry is back to what db/seeds/base_world/ says."
  end
end

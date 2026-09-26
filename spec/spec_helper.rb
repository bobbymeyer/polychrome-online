# frozen_string_literal: true

require_relative "../lib/battle"
require_relative "../lib/pointcrawl"
require_relative "../lib/generators"
Dir[File.join(__dir__, "support", "**", "*.rb")].sort.each { |f| require f }

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |m|
    m.verify_partial_doubles = true
  end
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.include BattleHelpers
end

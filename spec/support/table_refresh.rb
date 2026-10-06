# frozen_string_literal: true

# The table's refresh is broadcast from a job (Campaign#table_changed): run
# it inside the block, so what it broadcasts is seen there. The spec
# includes ActiveJob::TestHelper.
module TableRefresh
  def refreshing_the_table(&) = perform_enqueued_jobs(only: Turbo::Streams::BroadcastStreamJob, &)
end

RSpec.configure do |config|
  %i[model request].each do |type|
    config.include TableRefresh, type: type
  end
end

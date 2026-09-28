# frozen_string_literal: true

# Stands in for Cutout::Client in specs: records what it's sent and answers
# with a transparent PNG (FakeComfy.png), or raises what it's told to.
class FakeCutout
  attr_reader :sent

  def initialize(raises: nil)
    @sent = []
    @raises = raises
  end

  def remove(bytes)
    @sent << bytes
    raise @raises if @raises

    FakeComfy.png
  end
end

# The background remover never reached for over the network in specs.
RSpec.configure do |config|
  config.before { allow(Cutout).to receive(:client).and_return(FakeCutout.new) if defined?(Cutout) }
end

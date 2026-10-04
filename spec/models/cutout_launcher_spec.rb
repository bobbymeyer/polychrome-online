# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cutout::Launcher do
  let(:local) { Rails.configuration.x.cutout.merge(url: "http://127.0.0.1:7000", autostart: "1") }
  let(:spawned) { [] }
  let(:spawner) { ->(env, command, **options) { spawned << [ env, command, options ]; 4242 } }

  before do
    allow(Process).to receive(:detach)
    allow(described_class).to receive(:starting?).and_return(false)
    allow(File).to receive(:write).and_call_original
    allow(File).to receive(:write).with(Rails.root.join(described_class::PID_FILE), "4242")
    allow(File).to receive(:open).and_call_original
    allow(File).to receive(:open).with(Rails.root.join(described_class::LOG_FILE), "a").and_return(StringIO.new)
  end

  it "starts bin/cutout on this machine when nothing answers, and is satisfied once it does" do
    polls = 0
    open = ->(_host, _port) { (polls += 1) > 2 }
    expect(described_class.ensure_running!(config: local, spawner: spawner, open: open, wait: 10, sleeper: ->(_) { })).to be(true)
    expect(spawned.size).to eq(1)
    env, command, options = spawned.first
    expect(env).to eq("CUTOUT_PORT" => "7000")
    expect(command).to end_with("bin/cutout")
    expect(options).to include(pgroup: true)
  end

  it "says it's starting, not failed, when it isn't up in time: the batch waits and tries again" do
    expect { described_class.ensure_running!(config: local, spawner: spawner, open: ->(*) { false }, wait: 0, sleeper: ->(_) { }) }
      .to raise_error(Cutout::Unreachable, /is starting at 127.0.0.1:7000/)
    expect(spawned.size).to eq(1)
  end

  it "does nothing for a remover elsewhere, one already answering, one already starting, or when told not to" do
    expect(described_class.ensure_running!(config: local.merge(url: "http://host.docker.internal:7000"), spawner: spawner, open: ->(*) { false })).to be(true)
    expect(described_class.ensure_running!(config: local, spawner: spawner, open: ->(*) { true })).to be(true)
    expect(described_class.ensure_running!(config: local.merge(autostart: "0"), spawner: spawner, open: ->(*) { false })).to be(true)
    allow(described_class).to receive(:starting?).and_return(true)
    expect { described_class.ensure_running!(config: local, spawner: spawner, open: ->(*) { false }, wait: 0, sleeper: ->(_) { }) }.to raise_error(Cutout::Unreachable)
    expect(spawned).to be_empty
  end

  it "is off in the test environment, and on by default otherwise" do
    expect(described_class.wanted?).to be(false)
    expect(described_class.wanted?(url: "http://127.0.0.1:7000", autostart: "1")).to be(true)
    expect(described_class.wanted?(url: "", autostart: "1")).to be(false)
  end
end

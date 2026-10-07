# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::Client do
  let(:reply) { { "choices" => [ { "message" => { "content" => "<think>hm</think>ready" } } ] } }

  it "asks the chat completions call and reads the reply, without the model's thinking" do
    http = FakeHttp.new("/v1/chat/completions" => [ 200, reply ])
    expect(described_class.new(url: "http://llm.test/v1", model: "qwen", http: http).chat(system: "s", user: "u")).to eq("ready")
    expect(JSON.parse(http.requests.sole.body)).to include("model" => "qwen", "messages" => [ { "role" => "system", "content" => "s" }, { "role" => "user", "content" => "u" } ])
  end

  it "sends a bearer token and any headers a proxy wants, and basic auth from the URL without ever showing it" do
    http = FakeHttp.new("/api/chat/completions" => [ 200, reply ])
    described_class.new(url: "https://me:s3cret@llm.example/api", token: "tok", headers: '{"CF-Access-Client-Id": "id"}', http: http).chat(system: "s", user: "u")
    request = http.requests.sole
    expect(request["Authorization"]).to start_with("Basic ") # basic auth from the URL is applied last
    expect(request["CF-Access-Client-Id"]).to eq("id")

    bearer = FakeHttp.new("/chat/completions" => [ 200, reply ])
    described_class.new(url: "http://llm.test", token: "tok", http: bearer).chat(system: "s", user: "u")
    expect(bearer.requests.sole["Authorization"]).to eq("Bearer tok")
  end

  it "explains a refusal, and says where it tried when nothing answers, as something worth trying again" do
    refused = FakeHttp.new("/chat/completions" => [ 400, { "error" => { "message" => "no such model" } } ])
    expect { described_class.new(url: "http://llm.test", http: refused).chat(system: "s", user: "u") }
      .to raise_error(Llm::Error, "The language model answered 400: no such model")
    expect { described_class.new(url: "http://me:s3cret@llm.test", http: FakeHttp.new({})).chat(system: "s", user: "u") }
      .to raise_error(Llm::Unreachable, /isn't reachable at http:\/\/llm.test/) { |e| expect(e.message).not_to include("s3cret") }
  end

  it "reads a refusal whose error is plain text (Ollama), and gets by with a body that isn't an error at all" do
    plain = FakeHttp.new("/chat/completions" => [ 404, { "error" => "model 'qwen' not found" } ])
    expect { described_class.new(url: "http://llm.test", http: plain).chat(system: "s", user: "u") }
      .to raise_error(Llm::Error, "The language model answered 404: model 'qwen' not found")
    listed = FakeHttp.new("/chat/completions" => [ 500, [ "oops" ] ])
    expect { described_class.new(url: "http://llm.test", http: listed).chat(system: "s", user: "u") }
      .to raise_error(Llm::Error, "The language model answered 500")
  end
end

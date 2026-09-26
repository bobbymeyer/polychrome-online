# frozen_string_literal: true

require "rails_helper"

RSpec.describe Comfy::Client do
  # Answers requests from a table of path => [status, body], recording them.
  class FakeHttp
    attr_reader :requests

    def initialize(routes) = (@routes = routes) && (@requests = [])

    def request(req)
      @requests << req
      status, body = @routes.fetch(req.path.split("?").first) { raise Errno::ECONNREFUSED }
      Net::HTTPResponse::CODE_TO_OBJ.fetch(status.to_s).new("1.1", status.to_s, "").tap do |response|
        response.instance_variable_set(:@body, body.is_a?(String) ? body : JSON.generate(body))
        response.instance_variable_set(:@read, true)
      end
    end
  end

  def client(routes) = described_class.new(url: "http://comfy.test", http: FakeHttp.new(routes))

  it "queues a graph and returns ComfyUI's prompt id" do
    http = FakeHttp.new("/prompt" => [ 200, { "prompt_id" => "abc" } ])
    expect(described_class.new(url: "http://comfy.test", http: http).submit({ "1" => {} }, client_id: "me")).to eq("abc")
    expect(JSON.parse(http.requests.sole.body)).to eq("prompt" => { "1" => {} }, "client_id" => "me")
  end

  it "explains a rejected graph with ComfyUI's node errors" do
    rejected = { "error" => { "message" => "Prompt outputs failed validation" },
                 "node_errors" => { "2" => { "class_type" => "LoraLoader", "errors" => [ { "message" => "Value not in list", "details" => "lora_name: 'nope' not in []" } ] } } }
    expect { client("/prompt" => [ 400, rejected ]).submit({}) }
      .to raise_error(Comfy::Error, "Prompt outputs failed validation · LoraLoader: lora_name: 'nope' not in []")
  end

  it "reads history: nothing yet, then the saved images" do
    expect(client("/history/abc" => [ 200, {} ]).result("abc")).to be_nil
    done = { "abc" => { "status" => { "status_str" => "success", "completed" => true },
                        "outputs" => { "9" => { "images" => [ { "filename" => "g_00001_.png", "subfolder" => "polychrome", "type" => "output" } ] } } } }
    expect(client("/history/abc" => [ 200, done ]).result("abc")).to eq([ { "filename" => "g_00001_.png", "subfolder" => "polychrome", "type" => "output" } ])
  end

  it "raises the execution error when a run failed" do
    failed = { "abc" => { "status" => { "status_str" => "error", "completed" => false,
                                        "messages" => [ [ "execution_error", { "node_type" => "KSampler", "exception_message" => "out of memory" } ] ] } } }
    expect { client("/history/abc" => [ 200, failed ]).result("abc") }.to raise_error(Comfy::Error, "KSampler: out of memory")
  end

  it "downloads an image through /view" do
    http = FakeHttp.new("/view" => [ 200, "PNGBYTES" ])
    bytes = described_class.new(url: "http://comfy.test", http: http).fetch("filename" => "a b.png", "subfolder" => "polychrome", "type" => "output")
    expect(bytes).to eq("PNGBYTES")
    expect(http.requests.sole.path).to eq("/view?filename=a+b.png&subfolder=polychrome&type=output")
  end

  it "lists installed LoRAs and checkpoints, and nothing when unreachable" do
    info = { "LoraLoader" => { "input" => { "required" => { "lora_name" => [ [ "a.safetensors", "b.safetensors" ] ] } } } }
    expect(client("/object_info/LoraLoader" => [ 200, info ]).loras).to eq(%w[a.safetensors b.safetensors])
    expect(client({}).checkpoints).to eq([])
  end

  it "says where it tried when ComfyUI isn't there" do
    expect { client({}).submit({}) }.to raise_error(Comfy::Error, /isn't reachable at http:\/\/comfy.test/)
    expect(client({})).not_to be_reachable
  end
end

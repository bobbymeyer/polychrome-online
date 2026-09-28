# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The app's settings (SiteSetting)", type: :request do
  it "lets an admin say where ComfyUI and the language model are, over the environment's" do
    get settings_path
    expect(response.body).to include("ComfyUI", "Language model", "Check the connection")
    expect(Comfy.config[:url]).to eq("http://comfy.test")
    expect(Llm).not_to be_enabled

    patch settings_path, params: { site_setting: { comfy_url: "http://host.docker.internal:8188", comfy_model: "anima-preview.safetensors",
                                                   rembg_node: "", llm_url: "http://host.docker.internal:8090/v1", llm_model: "qwen3" } }
    expect(response).to redirect_to(settings_path(check: 1, anchor: "connection"))
    expect(Comfy.config[:url]).to eq("http://host.docker.internal:8188")
    expect(Comfy.config[:families]).to be_present # the rest still from config
    expect(Llm).to be_enabled
    expect(Llm.config[:model]).to eq("qwen3")

    patch settings_path, params: { site_setting: { comfy_url: "", llm_url: "" } }
    expect(Comfy.config[:url]).to eq("http://comfy.test") # blank: back to the environment
    expect(Llm).not_to be_enabled
  end

  it "keeps passwords out of the database, and wants real addresses" do
    patch settings_path, params: { site_setting: { comfy_url: "http://me:s3cret@comfy.lan:8188" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("can&#39;t hold a user or password")
    patch settings_path, params: { site_setting: { llm_url: "ftp://nope" } }
    expect(response.body).to include("must be an http:// or https:// address")
    expect(SiteSetting.count).to eq(0)
  end

  it "is for admins" do
    sign_in_as(make_user("Player"))
    get settings_path
    expect(response).to have_http_status(:see_other)
    patch settings_path, params: { site_setting: { comfy_url: "http://evil.test" } }
    expect(SiteSetting.count).to eq(0)
  end
end

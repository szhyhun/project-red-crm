require "rails_helper"

RSpec.describe "Action Cable Redis adapter" do
  it "loads with the application's Redis dependency" do
    expect { require "action_cable/subscription_adapter/redis" }.not_to raise_error
  end

  it "uses Redis in development so worker broadcasts reach the web process" do
    cable_config = YAML.safe_load(
      ERB.new(Rails.root.join("config/cable.yml").read).result,
      aliases: false
    )

    expect(cable_config.dig("development", "adapter")).to eq("redis")
  end
end

require "rails_helper"

RSpec.describe "Action Cable Redis adapter" do
  it "loads with the application's Redis dependency" do
    expect { require "action_cable/subscription_adapter/redis" }.not_to raise_error
  end
end

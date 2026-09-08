require "rails_helper"
require "yaml"

RSpec.describe "Resque recurring job schedule" do
  let(:schedule) do
    YAML.safe_load_file(Rails.root.join("config/resque_schedule.yml"), aliases: false)
  end

  it "keeps every recurring job explicit and reviewable" do
    expect(schedule).to include("conversation_retention")

    expect(schedule.fetch("conversation_retention")).to include(
      "class" => "Conversations::RetentionJob",
      "queue" => "maintenance"
    )

    schedule.each_value do |entry|
      expect(entry).to include("cron", "class", "queue", "description")
    end
  end
end

require "rails_helper"
require "yaml"

RSpec.describe "Resque recurring job schedule" do
  let(:schedule) do
    YAML.safe_load_file(Rails.root.join("config/resque_schedule.yml"), aliases: false)
  end

  it "keeps every recurring job explicit and reviewable" do
    expect(schedule).to include("conversation_retention", "aryeo_import_watchdog")

    expect(schedule.fetch("conversation_retention")).to include(
      "class" => "Conversations::RetentionJob",
      "queue" => "maintenance"
    )

    expect(schedule.fetch("aryeo_import_watchdog")).to include(
      "class" => "Aryeo::ImportWatchdogJob",
      "queue" => "maintenance"
    )

    schedule.each_value do |entry|
      expect(entry).to include("cron", "class", "queue", "description")
    end
  end
end

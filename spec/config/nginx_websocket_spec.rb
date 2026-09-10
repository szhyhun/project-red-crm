require "rails_helper"

RSpec.describe "Nginx WebSocket proxy configuration" do
  it "forwards upgrades for both temporary and bootstrap proxy templates" do
    temporary_config = Rails.root.join("deploy/nginx/project-red-crm-temporary-sslip.conf").read
    bootstrap_script = Rails.root.join("scripts/aws/bootstrap-production-host.sh").read

    [ temporary_config, bootstrap_script ].each do |config|
      expect(config).to include("proxy_http_version 1.1")
      expect(config).to include("proxy_set_header Upgrade $http_upgrade;")
      expect(config).to include("proxy_set_header Connection $connection_upgrade;")
      expect(config).to include("map $http_upgrade $connection_upgrade")
    end
  end
end

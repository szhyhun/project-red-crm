require "rails_helper"

RSpec.describe "Nginx WebSocket proxy configuration" do
  it "forwards upgrades for both temporary and bootstrap proxy templates" do
    temporary_config = Rails.root.join("deploy/nginx/project-red-crm-temporary-sslip.conf").read
    bootstrap_script = Rails.root.join("scripts/aws/bootstrap-production-host.sh").read
    release_script = Rails.root.join("scripts/aws/deploy-release-on-host.sh").read
    websocket_script = Rails.root.join("scripts/aws/configure-nginx-websocket.sh").read

    [ temporary_config, bootstrap_script ].each do |config|
      expect(config).to include("proxy_http_version 1.1")
      expect(config).to include("proxy_set_header Upgrade $http_upgrade;")
      expect(config).to include("proxy_set_header Connection $connection_upgrade;")
      expect(config).to include("map $http_upgrade $connection_upgrade")
    end

    expect(release_script).to include("configure-nginx-websocket.sh")
    expect(websocket_script).to include("nginx -t")
    expect(websocket_script).to include("systemctl reload nginx")
  end
end

namespace :project_red do
  desc "Seed the ProjectRed development organization and owner account"
  task seed_development: :environment do
    organization = Organization.find_or_create_by!(slug: "projectred") do |record|
      record.name = "ProjectRed"
      record.time_zone = "America/Vancouver"
    end

    puts "Seeded #{organization.name} (#{organization.slug})"
  end
end

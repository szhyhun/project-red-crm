require "resque/scheduler/tasks"

namespace :resque do
  # Resque Scheduler's task depends on this setup task. Loading the schedule
  # here keeps normal workers and the scheduler on the same Redis/application
  # configuration while the YAML file remains the single schedule registry.
  task setup: :environment do
    require Rails.root.join("app/jobs/conversations/retention_job")
    require Rails.root.join("app/jobs/aryeo/import_watchdog_job")

    schedule_path = Rails.root.join("config/resque_schedule.yml")
    Resque.schedule = YAML.safe_load_file(schedule_path, aliases: false)
  end
end

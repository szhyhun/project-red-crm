require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ProjectRedCrm
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true
    config.time_zone = "Pacific Time (US & Canada)"
    config.active_job.queue_adapter = :resque
    config.autoload_paths << Rails.root.join("app/services")
    config.eager_load_paths << Rails.root.join("app/services")

    # The separate Next portal authenticates with an HttpOnly Rails session.
    #
    # These must be inserted *before* Warden::Manager rather than appended with
    # `use`: appending puts them inside Warden, so Warden commits the signed-in
    # user to the session after the cookie for that response has already been
    # written, and the next request arrives with nothing to restore.
    config.middleware.insert_before Warden::Manager, ActionDispatch::Cookies
    config.middleware.insert_before Warden::Manager, ActionDispatch::Session::CookieStore,
                                    key: "_project_red_crm_session",
                                    same_site: :lax,
                                    secure: Rails.env.production?
  end
end

require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module DrLerouxReceptionist
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Africa/Johannesburg"
    # config.eager_load_paths << Rails.root.join("extras")

    # Session store for Inertia dashboard (middleware already included via rails/all).
    # secure:false — assume_ssl (needed for the Twilio webhook) would otherwise mark this
    # cookie Secure, but reception reaches the dashboard over plain http (LAN/Tailscale) and
    # browsers drop Secure cookies there → per-user login can't hold a session. The dashboard
    # is internal-only (the public tunnel blocks it) + httponly + same_site lax, so this is safe.
    config.session_store :cookie_store, key: "_dr_leroux_receptionist_session", secure: false, same_site: :lax

    # Route exceptions through our own ErrorsController so Inertia renders
    # branded 404/422/500 pages instead of the default Rails HTML pages.
    config.exceptions_app = self.routes
  end
end

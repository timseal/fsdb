require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

module FsdbWeb
  class Application < Rails::Application
    config.load_defaults 8.1

    # Autoload lib/fsdb so the gem modules are available to Rails
    config.autoload_lib(ignore: %w[assets tasks])

    config.generators.system_tests = nil
  end
end

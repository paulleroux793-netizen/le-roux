# frozen_string_literal: true

InertiaRails.configure do |config|
  config.version = ViteRuby.digest
  config.encrypt_history = true
  config.always_include_errors_hash = true
  config.use_script_element_for_initial_page = false
  config.use_data_inertia_head_attribute = true
  config.root_dom_id = "app"
end

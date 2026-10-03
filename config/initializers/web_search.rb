# A mistyped provider order fails the boot, not every web lookup Halon makes.
Rails.application.config.after_initialize { Integrations::WebSearch.check_order! }

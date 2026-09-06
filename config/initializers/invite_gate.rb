# Require an invite code for new workspace installs. Off by default.
Rails.application.config.x.invite_required = ActiveModel::Type::Boolean.new.cast(ENV.fetch("INVITE_REQUIRED", "false"))

# Whether a new workspace needs an invite code to install. Off by default, so a
# fresh checkout and hosted production both let anyone install. Turn it on to
# run a private instance or a closed beta.
Rails.application.config.x.invite_required = ActiveModel::Type::Boolean.new.cast(ENV.fetch("INVITE_REQUIRED", "false"))

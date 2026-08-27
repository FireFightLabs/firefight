namespace :members do
  # Members provisioned from Slack events (commands, button clicks) before the
  # bot had the users:read.email scope got a synthetic
  # "<slack_user_id>@users.slack.<team_id>" email. Once the bot has the scope and
  # the workspace has re-installed the app, this re-fetches their profile and
  # writes the real email. Idempotent — already-real emails no longer match.
  desc "Backfill real emails for members with a synthetic @users.slack placeholder"
  task backfill_emails: :environment do
    memberships = WorkspaceMembership
      .joins(:user)
      .where("users.email LIKE ?", "%@users.slack.%")
      .includes(:user, :workspace)

    updated = 0
    skipped = 0

    memberships.find_each do |membership|
      user = membership.user
      synthetic = "#{membership.platform_user_id}@users.slack.#{membership.workspace.platform_id}"

      # Only touch genuinely synthetic addresses, never a real email that happens
      # to match the LIKE.
      unless user.email == synthetic
        skipped += 1
        next
      end

      profile = WorkspaceAdapter.for(membership.workspace).get_user_info(user_id: membership.platform_user_id)
      email = profile[:email].presence

      if email.nil?
        warn "Skipped #{user.id} (#{membership.workspace.name}): Slack returned no email — check the bot has users:read.email and the app was re-installed."
        skipped += 1
        next
      end

      # A real-email user already exists (e.g. they also signed in via OIDC).
      # Merging identities can orphan FKs, so flag for manual resolution.
      if User.where.not(id: user.id).exists?(email: email)
        warn "Skipped #{user.id}: real email #{email} already belongs to another user — resolve manually."
        skipped += 1
        next
      end

      user.update!(email: email)
      updated += 1
      puts "Updated #{user.id}: #{email}"
    rescue AdapterError => e
      warn "Skipped membership #{membership.id}: #{e.message}"
      skipped += 1
    end

    puts "Backfill complete: #{updated} updated, #{skipped} skipped."
  end
end

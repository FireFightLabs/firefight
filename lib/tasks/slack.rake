namespace :slack do
  desc "Refresh token for a specific workspace by ID"
  task :refresh_workspace, [ :workspace_id ] => :environment do |t, args|
    if args[:workspace_id].blank?
      puts "❌ Error: workspace_id is required"
      puts "Usage: bin/rails slack:refresh_workspace[workspace-uuid]"
      exit 1
    end

    workspace = Workspace.find_by(id: args[:workspace_id])

    unless workspace
      puts "❌ Error: Workspace not found with ID: #{args[:workspace_id]}"
      exit 1
    end

    puts "🔄 Refreshing token for workspace: #{workspace.name} (#{workspace.platform})"

    manager = Slack::TokenManager.new

    if manager.refresh_workspace(workspace)
      puts "✅ Successfully refreshed token for #{workspace.name}"
      puts "   Expires at: #{workspace.reload.token_expires_at}"
    else
      puts "❌ Failed to refresh token for #{workspace.name}"
      puts "   Check logs for details"
      exit 1
    end
  end

  desc "Refresh all expiring workspace tokens"
  task refresh_all_expiring: :environment do
    puts "🔄 Refreshing all expiring tokens..."

    manager = Slack::TokenManager.new
    results = manager.refresh_all_expiring

    puts "\n📊 Results:"
    puts "   Workspaces: #{results[:workspaces][:succeeded]} succeeded, #{results[:workspaces][:failed]} failed"

    total_failed = results[:workspaces][:failed]
    if total_failed > 0
      puts "\n⚠️  Some tokens failed to refresh. Check logs for details."
      exit 1
    else
      puts "\n✅ All tokens refreshed successfully!"
    end
  end

  desc "Force refresh all workspace tokens (ignore expiration)"
  task force_refresh_all_workspaces: :environment do
    puts "🔄 Force refreshing ALL workspace tokens..."

    manager = Slack::TokenManager.new
    succeeded = 0
    failed = 0

    Workspace.slack_platform.find_each do |workspace|
      if manager.refresh_workspace(workspace)
        succeeded += 1
        puts "✅ #{workspace.name}"
      else
        failed += 1
        puts "❌ #{workspace.name}"
      end
    end

    puts "\n📊 Results: #{succeeded} succeeded, #{failed} failed"

    if failed > 0
      puts "\n⚠️  Some tokens failed to refresh. Check logs for details."
      exit 1
    else
      puts "\n✅ All workspace tokens refreshed!"
    end
  end

  desc "[Dev] Archive ALL incident channels for a workspace, regardless of status"
  task :archive_all_incident_channels, [ :workspace_id ] => :environment do |t, args|
    abort "Error: workspace_id is required\nUsage: bin/rails 'slack:archive_all_incident_channels[workspace-uuid]'" if args[:workspace_id].blank?

    workspace = Workspace.find_by(id: args[:workspace_id])
    abort "Error: Workspace not found with ID: #{args[:workspace_id]}" unless workspace

    incidents = workspace.incidents
      .where.not(channel_id: nil)
      .where(channel_archived_at: nil)

    puts "Archiving ALL incident channels for #{workspace.name} (#{incidents.count} channels)..."

    adapter = Slack::WorkspaceAdapter.new(workspace)
    archived = 0
    failed = 0

    incidents.find_each do |incident|
      adapter.archive_channel(channel_id: incident.channel_id)
      incident.update!(
        channel_archived_at: Time.current,
        channel_archived_by: "rake:slack:archive_all_incident_channels"
      )
      archived += 1
      puts "  Archived: #{incident.identifier} (#{incident.channel_name})"
    rescue AdapterError::AlreadyArchived
      incident.update!(
        channel_archived_at: Time.current,
        channel_archived_by: "rake:slack:archive_all_incident_channels"
      )
      archived += 1
      puts "  Already archived: #{incident.identifier} (#{incident.channel_name})"
    rescue => e
      failed += 1
      puts "  Failed: #{incident.identifier} (#{incident.channel_name}) - #{e.message}"
    end

    puts "\nDone: #{archived} archived, #{failed} failed"
  end

  desc "Archive Slack channels for closed incidents. Required: workspace_id. Optional: days"
  task :archive_incident_channels, [ :workspace_id, :days ] => :environment do |t, args|
    if args[:workspace_id].blank?
      puts "Error: workspace_id is required"
      puts "Usage: bin/rails slack:archive_incident_channels[workspace-uuid]"
      puts "       bin/rails slack:archive_incident_channels[workspace-uuid,5]"
      exit 1
    end

    workspace = Workspace.find_by(id: args[:workspace_id])

    unless workspace
      puts "Error: Workspace not found with ID: #{args[:workspace_id]}"
      exit 1
    end

    incidents = workspace.incidents
      .closed
      .where.not(channel_id: nil)
      .where(channel_archived_at: nil)

    if args[:days].present?
      days = args[:days].to_i
      incidents = incidents.where("resolved_at < ?", days.days.ago)
      puts "Archiving channels for incidents resolved more than #{days} days ago..."
    else
      puts "Archiving channels for all closed incidents..."
    end

    adapter = Slack::WorkspaceAdapter.new(workspace)
    archived = 0
    failed = 0

    incidents.find_each do |incident|
      adapter.archive_channel(channel_id: incident.channel_id)
      incident.update!(
        channel_archived_at: Time.current,
        channel_archived_by: "rake:slack:archive_incident_channels"
      )
      archived += 1
      puts "  Archived: #{incident.identifier} (#{incident.channel_name})"
    rescue AdapterError::AlreadyArchived
      incident.update!(
        channel_archived_at: Time.current,
        channel_archived_by: "rake:slack:archive_incident_channels"
      )
      archived += 1
      puts "  Already archived: #{incident.identifier} (#{incident.channel_name})"
    rescue => e
      failed += 1
      puts "  Failed: #{incident.identifier} (#{incident.channel_name}) - #{e.message}"
    end

    puts "\nDone: #{archived} archived, #{failed} failed"
  end

  desc "List all workspaces with token expiration info"
  task list_workspaces: :environment do
    workspaces = Workspace.slack_platform.order(:name)

    if workspaces.empty?
      puts "No Slack workspaces found."
      exit 0
    end

    puts "\n📋 Slack Workspaces:\n\n"

    workspaces.each do |workspace|
      puts "  #{workspace.name}"
      puts "    ID: #{workspace.id}"
      puts "    Platform ID: #{workspace.platform_id}"

      if workspace.token_expires_at.present?
        time_until_expiry = workspace.token_expires_at - Time.current
        hours_until_expiry = (time_until_expiry / 3600).round(1)

        status = if time_until_expiry <= 0
          "❌ EXPIRED"
        elsif time_until_expiry <= 3.hours
          "⚠️  EXPIRING SOON"
        else
          "✅ OK"
        end

        puts "    Token expires: #{workspace.token_expires_at} (in #{hours_until_expiry}h) #{status}"
      else
        puts "    Token expires: Never (no expiration set)"
      end

      puts "    Has refresh token: #{workspace.refresh_token.present? ? 'Yes' : 'No'}"
      puts ""
    end
  end
end

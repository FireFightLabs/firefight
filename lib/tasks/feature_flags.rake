namespace :feature_flags do
  desc "Turn a feature flag on for one workspace: rake 'feature_flags:enable[FLAG,WORKSPACE_ID]'"
  task :enable, [ :flag, :workspace_id ] => :environment do |_, args|
    workspace = Workspace.find(args[:workspace_id])
    FeatureFlags.enable!(workspace, args[:flag])
    puts "Turned #{args[:flag]} on for #{workspace.name} (#{workspace.id})."
  rescue ActiveRecord::RecordNotFound
    abort "No workspace with id #{args[:workspace_id].inspect}."
  rescue FeatureFlags::UnknownFlag => e
    abort "#{e.message}. Known flags: #{FeatureFlags::ALL.join(', ')}."
  end

  desc "Turn a feature flag off for one workspace: rake 'feature_flags:disable[FLAG,WORKSPACE_ID]'"
  task :disable, [ :flag, :workspace_id ] => :environment do |_, args|
    workspace = Workspace.find(args[:workspace_id])
    FeatureFlags.disable!(workspace, args[:flag])
    puts "Turned #{args[:flag]} off for #{workspace.name} (#{workspace.id})."
  rescue ActiveRecord::RecordNotFound
    abort "No workspace with id #{args[:workspace_id].inspect}."
  rescue FeatureFlags::UnknownFlag => e
    abort "#{e.message}. Known flags: #{FeatureFlags::ALL.join(', ')}."
  end

  desc "List every feature flag and the workspaces it is on for"
  task list: :environment do
    FeatureFlags::ALL.each do |flag|
      workspaces = FeatureFlags.workspaces_with(flag).order(:name)
      if workspaces.empty?
        puts "#{flag}: off for every workspace"
      else
        puts "#{flag}: #{workspaces.map { |workspace| "#{workspace.name} (#{workspace.id})" }.join(', ')}"
      end
    end
  end
end

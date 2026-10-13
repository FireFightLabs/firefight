namespace :library do
  desc "Give each of Firefight's library items whose words changed its next version, in config/library_versions.yml"
  task versions: :environment do
    changed = FirefightLibrary.stale
    FirefightLibrary.write!
    puts changed.empty? ? "Every version is current." : changed.map { |kind, names| "#{kind}: #{names.join(', ')}" }.join("\n")
  end
end

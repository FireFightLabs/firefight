namespace :typescript do
  desc "Regenerate app/frontend/lib/generated/constants.ts from Ruby constants"
  task constants: :environment do
    TypescriptConstants.write!
    puts "Wrote #{TypescriptConstants::OUTPUT.relative_path_from(Rails.root)}"
  end
end

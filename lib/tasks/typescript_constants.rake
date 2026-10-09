namespace :typescript do
  desc "Regenerate the frontend's generated constants from Ruby constants, the app's and the operator console's"
  task constants: :environment do
    [ TypescriptConstants, Operator::TypescriptConstants ].each do |generator|
      generator.write!
      puts "Wrote #{generator::OUTPUT.relative_path_from(Rails.root)}"
    end
  end
end

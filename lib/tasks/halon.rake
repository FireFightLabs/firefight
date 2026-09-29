# Measuring Halon. Both run where nobody in the workspace sees them, see Investigation::Rehearsal.
namespace :halon do
  desc "Replay a finished investigation on another model: bin/rails 'halon:replay[INVESTIGATION_ID,MODEL,PROVIDER]'"
  task :replay, %i[investigation model provider] => :environment do |_task, args|
    original = Investigation.find(args[:investigation])
    replay = Investigation::Rehearsal.replay!(original, model: args[:model], provider: args[:provider])

    [ [ "Original", Investigation::Rehearsal.summarize(original) ], [ "Replay", replay ] ].each do |label, result|
      puts "#{label}: #{result.model} #{result.status}, #{result.turns} turns, #{result.spent_cents} cents, #{result.steps} steps" \
           "#{", #{result.not_recorded} not recorded" if result.not_recorded.positive?}"
      puts "  #{result.summary || 'No finding'}"
      result.claims.each { |claim| puts "  - #{claim}" }
    end
  end

  # A case is a mapping with workspace (an id), said (what the person asked) and expect (texts the finding must name).
  # incident (its identifier) is optional, and without it the case is asked as a question. as_of maps a repository to the
  # commit it is read as of, the one before the fix for a bug taken from history. Cases can name private repositories,
  # so they live outside this repository.
  desc "Run incidents whose cause is known and score the findings: bin/rails 'halon:bench[CASES_YAML,MODEL,PROVIDER]'"
  task :bench, %i[cases model provider] => :environment do |_task, args|
    cases = YAML.safe_load_file(args[:cases])
    results = cases.map do |bench_case|
      workspace = Workspace.find(bench_case["workspace"])
      incident = workspace.incidents.find_by!(identifier: bench_case["incident"]) if bench_case["incident"]
      result = Investigation::Rehearsal.bench!(
        workspace, said: bench_case["said"], incident: incident, as_of: bench_case["as_of"].to_h, model: args[:model], provider: args[:provider]
      )
      found = result.names?(bench_case["expect"])
      puts "#{found ? 'FOUND ' : 'MISSED'} #{bench_case['name']}: #{result.turns} turns, #{result.spent_cents} cents, #{result.seconds}s"
      puts "  #{result.summary || 'No finding'}"
      [ found, result ]
    end
    found = results.count(&:first)
    spent = results.sum { |_found, result| result.spent_cents }.round(2)
    puts "\n#{found} of #{results.size} found, #{spent} cents#{", #{(spent / found).round(2)} cents per cause found" if found.positive?}"
  end
end

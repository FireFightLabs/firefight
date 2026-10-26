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

  # A case is a mapping with workspace (an id), incident (its identifier), said (what the person asked) and expect
  # (texts the finding must name). Cases can name private repositories, so they live outside this repository.
  desc "Run incidents whose cause is known and score the findings: bin/rails 'halon:bench[CASES_YAML,MODEL,PROVIDER]'"
  task :bench, %i[cases model provider] => :environment do |_task, args|
    cases = YAML.safe_load_file(args[:cases])
    results = cases.map do |bench_case|
      incident = Workspace.find(bench_case["workspace"]).incidents.find_by!(identifier: bench_case["incident"])
      result = Investigation::Rehearsal.bench!(incident, said: bench_case["said"], model: args[:model], provider: args[:provider])
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

# The chat bench, see Conversation::Bench. Scenarios live in config/halon_bench, written from real failures.
namespace :halon do
  # SCENARIOS picks some by key, comma separated. LABEL names the run, such as a commit. OUT writes the scores to a file
  # that halon:chat_bench_compare reads. REPEATS, or the third argument, is how often each scenario is replayed (3), and
  # BUDGET, or the fourth, the dollars the run may spend on Halon and the judge together (2). A run that reaches its
  # budget stops, says so and reports what scored before it.
  desc "Replay the chat bench's scenarios and score them: bin/rails 'halon:chat_bench[MODEL,PROVIDER,REPEATS,BUDGET]'"
  task :chat_bench, %i[model provider repeats budget] => :environment do |_task, args|
    trigger = ENV["CI"].present? ? Conversation::BenchRun::TRIGGER_CI : Conversation::BenchRun::TRIGGER_TERMINAL
    keys = ENV["SCENARIOS"].to_s.split(",").map(&:strip).presence
    repeats = (args[:repeats].presence || ENV["REPEATS"].presence)&.to_i
    budget = (args[:budget].presence || ENV["BUDGET"].presence)&.to_f
    # A small pool of its own, one connection per replay and one for the run, on a server others share.
    ActiveRecord::Base.establish_connection(ActiveRecord::Base.connection_db_config.configuration_hash.except(:pool).merge(max_connections: Conversation::Bench::AT_ONCE + 1))
    run = Conversation::Bench.run!(trigger: trigger, model: args[:model], provider: args[:provider], label: ENV["LABEL"], keys: keys, repeats: repeats,
                                   budget_micros: budget && (budget * Conversation::BenchRun::MICROS_PER_DOLLAR).round) do |result|
      puts Conversation::BenchReport.replay(result)
      result.notes.each { |note| puts "  - #{note}" }
    end
    puts Conversation::BenchReport.run(run)
    File.write(ENV["OUT"], JSON.pretty_generate(Conversation::BenchComparison.export(run))) if ENV["OUT"].present?
    # A run that reached its budget stopped as asked, and what scored before it stands.
    next puts("\n#{run.stopped_reason}") if run.stopped_at_budget? && run.results.scored.exists?

    abort "\n#{run.stopped_reason}" if run.stopped?
    abort "Some scenarios could not finish, so this run cannot vouch for them." if run.results.where(status: Conversation::BenchResult::STATUS_ERRORED).exists?
  rescue Conversation::Bench::Busy, Conversation::BenchKeys::Missing, ActiveRecord::RecordInvalid => refused
    abort refused.message
  end

  # Each side is a run's id or a file halon:chat_bench wrote with OUT, each scenario the mean of its repeats with their
  # spread. Fails when the second side's total dropped by more than the noise, the tolerance or the spread either run
  # saw between its own passes.
  desc "Compare two chat bench runs: bin/rails 'halon:chat_bench_compare[BASE,HEAD]'"
  task :chat_bench_compare, %i[base head] => :environment do |_task, args|
    side = ->(name) { File.exist?(name.to_s) ? JSON.parse(File.read(name)) : Conversation::BenchComparison.export(Conversation::BenchRun.find(name)) }
    base = side.call(args[:base])
    head = side.call(args[:head])
    comparison = Conversation::BenchComparison.from_exports(base, head)
    shown = ->(tally) { tally&.total ? "#{format('%.2f', tally.total)}#{format(' (%.2f)', tally.spread) if tally.spread}" : "   -" }

    comparison.rows.each do |row|
      change = row.both? ? format("%+.2f", row.delta) : ""
      puts "#{shown.call(row.base)} -> #{shown.call(row.head)} #{change.rjust(6)}  #{row.scenario}"
    end
    puts "\nBase, prompt #{base['prompt_version']} on #{base['model']}: #{comparison.base_total || 'nothing scored'}"
    puts "Head, prompt #{head['prompt_version']} on #{head['model']}: #{comparison.head_total || 'nothing scored'}"
    [ :quality, *Conversation::BenchScore.dimensions ].each do |name|
      puts "  #{name}: #{comparison.dimension(:base, name) || '-'} -> #{comparison.dimension(:head, name) || '-'}"
    end
    puts "Noise allowed: #{comparison.noise}"
    puts "\nThe two runs used different models, so a drop here says nothing about the change." unless comparison.comparable?
    if comparison.failed?
      worst = comparison.worse.map(&:scenario)
      abort "\nThe score dropped by more than #{comparison.noise}.#{" Read #{worst.to_sentence} first." if worst.any?}"
    end
  end

  desc "Replay a real chat from its record and score it: bin/rails 'halon:chat_replay[CONVERSATION_ID,MODEL,PROVIDER]'"
  task :chat_replay, %i[conversation model provider] => :environment do |_task, args|
    conversation = Conversation.find(args[:conversation])
    run = Conversation::Bench.replay_chat!(conversation, trigger: Conversation::BenchRun::TRIGGER_TERMINAL, model: args[:model],
                                                         provider: args[:provider], label: ENV["LABEL"])
    result = run.results.sole
    puts Conversation::BenchReport.replay(result)
    result.notes.each { |note| puts "  - #{note}" }
    puts "  #{result.reason}" if result.reason.present?
    puts "\n#{result.answer}" if result.answer.present?
  rescue Conversation::Bench::Busy, Conversation::BenchKeys::Missing => refused
    abort refused.message
  end

  # Prints the chat as a scenario file. It holds the customer's words and data, so it is only a start. Replace them
  # with made up ones before it goes into config/halon_bench, and write down what a right answer reaches.
  # Nothing is left behind, since the tools are read as a member of a workspace made in a transaction rolled back.
  desc "Copy the bench's shared tools from their live definitions: bin/rails halon:bench_tools"
  task bench_tools: :environment do
    changed = Conversation::BenchTools.refresh!
    puts changed.any? ? "Refreshed #{changed.to_sentence} in #{Conversation::BenchCase::SHARED_TOOLS.relative_path_from(Rails.root)}." : "Every shared tool already matches."
  end

  desc "Write the big workspace's tools from their sources: bin/rails halon:bench_big_workspace"
  task bench_big_workspace: :environment do
    Conversation::BenchWorkspace.write!
    puts "Wrote #{Conversation::BenchWorkspace.build.size} tools to #{Conversation::BenchWorkspace::TOOLS.relative_path_from(Rails.root)}."
  end

  desc "Print a real chat as a bench scenario to edit: bin/rails 'halon:chat_capture[CONVERSATION_ID]'"
  task :chat_capture, %i[conversation] => :environment do |_task, args|
    puts Conversation::Rehearsal.capture(Conversation.find(args[:conversation])).to_h.to_yaml
  end
end

# Halon's pull request review, run to measure it (PullRequestReview::Rehearsal). Nothing is posted to the code host,
# nobody in the workspace sees it, and it pays with the bench's own key. HEAD and BASE pin the commits to review, such
# as one round another reviewer read, and default to the pull request as its code host shows it now. CENTS caps what it
# may spend (400). OUT writes the review as JSON to a file to score, and it is printed otherwise.
namespace :halon do
  desc "Review a pull request without posting anything: bin/rails 'halon:pr_review[WORKSPACE_ID,OWNER/REPO,NUMBER,HEAD,BASE,MODEL,PROVIDER,CENTS]'"
  task :pr_review, %i[workspace repository number head base model provider cents] => :environment do |_task, args|
    review = PullRequestReview::Rehearsal.run!(
      workspace: Workspace.find(args[:workspace]), repository: args[:repository], number: Integer(args[:number]), head_sha: args[:head], base_sha: args[:base],
      model: args[:model], provider: args[:provider], max_spend_cents: Integer(args[:cents].presence || 400)
    )
    result = JSON.pretty_generate(PullRequestReview::Rehearsal.to_h(review))
    ENV["OUT"].present? ? File.write(ENV["OUT"], result) : puts(result)
    puts "#{review.status}: #{review.findings.count} findings, #{review.spent_cents} cents, #{review.turns_used} turns"
  end
end

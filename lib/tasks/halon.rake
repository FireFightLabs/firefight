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
  bench_line = lambda do |result|
    if result.status == Conversation::BenchResult::STATUS_SCORED
      dimensions = Conversation::BenchScore.dimensions.map { |name| "#{name} #{result.public_send(name)&.round(2) || '-'}" }.join(", ")
      cents = (result.spent_micros / FirefightAi::AgentLoop::MICROS_PER_CENT.to_f).round(2)
      "#{format('%.2f', result.total)} #{result.scenario}: #{dimensions}, #{cents} cents, #{result.turns} turns"
    else
      "ERROR #{result.scenario}: #{result.reason}"
    end
  end

  bench_summary = lambda do |run|
    totals = run.results.scored.pluck(:total)
    spent = (run.results.sum(:spent_micros) / FirefightAi::AgentLoop::MICROS_PER_CENT.to_f).round(2)
    mean = totals.empty? ? "none" : (totals.sum / totals.size).round(3)
    "\nRun #{run.id}: #{totals.size} of #{run.results.size} scored, mean #{mean}, #{spent} cents, prompt #{run.prompt_version} on #{run.model}"
  end

  # SCENARIOS picks some by key, comma separated. LABEL names the run, such as a commit. OUT writes the scores to a file
  # that halon:chat_bench_compare reads.
  desc "Replay the chat bench's scenarios and score them: bin/rails 'halon:chat_bench[MODEL,PROVIDER]'"
  task :chat_bench, %i[model provider] => :environment do |_task, args|
    trigger = ENV["CI"].present? ? Conversation::BenchRun::TRIGGER_CI : Conversation::BenchRun::TRIGGER_TERMINAL
    keys = ENV["SCENARIOS"].to_s.split(",").map(&:strip).presence
    run = Conversation::Bench.run!(trigger: trigger, model: args[:model], provider: args[:provider], label: ENV["LABEL"], keys: keys) do |result|
      puts bench_line.call(result)
      result.notes.each { |note| puts "  - #{note}" }
    end
    puts bench_summary.call(run)
    File.write(ENV["OUT"], JSON.pretty_generate(Conversation::BenchComparison.export(run))) if ENV["OUT"].present?
    abort "Some scenarios could not finish, so this run cannot vouch for them." if run.results.where(status: Conversation::BenchResult::STATUS_ERRORED).exists?
  end

  # Each side is a run's id or a file halon:chat_bench wrote with OUT. Fails when the second side's total dropped by more
  # than the noise between two replays of the same model.
  desc "Compare two chat bench runs: bin/rails 'halon:chat_bench_compare[BASE,HEAD]'"
  task :chat_bench_compare, %i[base head] => :environment do |_task, args|
    side = ->(name) { File.exist?(name.to_s) ? JSON.parse(File.read(name)) : Conversation::BenchComparison.export(Conversation::BenchRun.find(name)) }
    base = side.call(args[:base])
    head = side.call(args[:head])
    comparison = Conversation::BenchComparison.from_exports(base, head)
    shown = ->(score) { score&.total ? format("%.2f", score.total) : "   -" }

    comparison.rows.each do |row|
      change = row.both? ? format("%+.2f", row.delta) : ""
      puts "#{shown.call(row.base)} -> #{shown.call(row.head)} #{change.rjust(6)}  #{row.scenario}"
    end
    puts "\nBase, prompt #{base['prompt_version']} on #{base['model']}: #{comparison.base_total || 'nothing scored'}"
    puts "Head, prompt #{head['prompt_version']} on #{head['model']}: #{comparison.head_total || 'nothing scored'}"
    Conversation::BenchScore.dimensions.each do |name|
      puts "  #{name}: #{comparison.dimension(:base, name) || '-'} -> #{comparison.dimension(:head, name) || '-'}"
    end
    puts "\nThe two runs used different models, so a drop here says nothing about the change." unless comparison.comparable?
    if comparison.failed?
      worst = comparison.worse.map(&:scenario)
      abort "\nThe score dropped by more than #{Conversation::BenchComparison::TOLERANCE}.#{" Read #{worst.to_sentence} first." if worst.any?}"
    end
  end

  desc "Replay a real chat from its record and score it: bin/rails 'halon:chat_replay[CONVERSATION_ID,MODEL,PROVIDER]'"
  task :chat_replay, %i[conversation model provider] => :environment do |_task, args|
    conversation = Conversation.find(args[:conversation])
    run = Conversation::Bench.replay_chat!(conversation, trigger: Conversation::BenchRun::TRIGGER_TERMINAL, model: args[:model],
                                                         provider: args[:provider], label: ENV["LABEL"])
    result = run.results.sole
    puts bench_line.call(result)
    result.notes.each { |note| puts "  - #{note}" }
    puts "  #{result.reason}" if result.reason.present?
    puts "\n#{result.answer}" if result.answer.present?
  end

  # Prints the chat as a scenario file. It holds the customer's words and data, so it is only a start. Replace them
  # with made up ones before it goes into config/halon_bench, and write down what a right answer reaches.
  # Nothing is left behind, since the tools are read as a member of a workspace made in a transaction rolled back.
  desc "Copy the bench's shared tools from their live definitions: bin/rails halon:bench_tools"
  task bench_tools: :environment do
    changed = Conversation::BenchTools.refresh!
    puts changed.any? ? "Refreshed #{changed.to_sentence} in #{Conversation::BenchCase::SHARED_TOOLS.relative_path_from(Rails.root)}." : "Every shared tool already matches."
  end

  desc "Print a real chat as a bench scenario to edit: bin/rails 'halon:chat_capture[CONVERSATION_ID]'"
  task :chat_capture, %i[conversation] => :environment do |_task, args|
    puts Conversation::Rehearsal.capture(Conversation.find(args[:conversation])).to_h.to_yaml
  end
end

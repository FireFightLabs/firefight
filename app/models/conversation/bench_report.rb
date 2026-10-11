# What the terminal prints for a chat bench run: a line for each replay as it settles, then each scenario's mean over its
# repeats with how far apart they lay, then the run's quality and cost apart, how many scenarios' repeats agree, and
# what it spent on Halon and on the judge.
module Conversation::BenchReport
  module_function

  def replay(result)
    label = result.bench_run.repeats > 1 ? "#{result.scenario} ##{result.attempt}" : result.scenario
    return "ERROR #{label}: #{result.reason}" unless result.status == Conversation::BenchResult::STATUS_SCORED

    scores = Conversation::BenchScore.dimensions.map { |name| "#{name} #{shown(result.public_send(name))}" }.join(", ")
    "#{shown(result.total)} #{label}: quality #{shown(result.quality)}, #{scores}, #{cents(result.spent_micros)} cents, #{result.turns} turns"
  end

  def run(run)
    tallies = Conversation::BenchTally.of_run(run)
    scored = tallies.select(&:scored?)
    halon = run.results.sum(:spent_micros)
    [
      "", "Each scenario over #{run.repeats} #{run.repeats == 1 ? 'replay' : 'replays'}, mean and (spread):",
      *tallies.map { |tally| scenario(tally) },
      "", "Run #{run.id}: #{scored.size} of #{tallies.size} scenarios scored, prompt #{run.prompt_version} on #{run.model}",
      "  total #{shown(mean(scored.map(&:total)))}, spread between passes #{shown(Conversation::BenchTally.spread(tallies))}",
      "  quality #{shown(mean(scored.map(&:quality)))}, cost #{shown(mean(scored.map { |tally| tally.score.cost }))}, " \
      "cited #{shown(mean(scored.map { |tally| tally.score.cited }))}",
      ("  repeats agree within #{Conversation::BenchRun::AGREEMENT} on #{Conversation::BenchTally.agreeing(tallies)} of " \
       "#{Conversation::BenchTally.repeated(tallies)} scenarios replayed more than once" if run.repeats > 1),
      "  spent #{cents(halon)} cents on Halon and #{cents(run.spent_micros_with_judge - halon)} cents on the judge" \
      "#{", of a budget of #{cents(run.budget_micros)} cents" if run.budget_micros}"
    ].compact.join("\n")
  end

  def scenario(tally)
    return "   -        #{tally.scenario}: nothing scored" unless tally.scored?

    "#{shown(tally.total)} (#{shown(tally.spread)}) #{tally.scenario}: quality #{shown(tally.quality)}, cost #{shown(tally.score.cost)}, " \
      "cited #{shown(tally.score.cited)}, #{tally.scored.size} of #{tally.replays.size} scored"
  end

  def shown(value) = value.nil? ? "-" : format("%.2f", value)

  def cents(micros) = (micros / FirefightAi::AgentLoop::MICROS_PER_CENT.to_f).round(2)

  def mean(values)
    given = values.compact
    given.empty? ? nil : (given.sum / given.size).round(3)
  end
end

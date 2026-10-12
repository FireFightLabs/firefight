# The steps a step waits for, by their positions in the watch. A step that waits for nothing is read at once, so steps
# that do not depend on each other go side by side. One whose prerequisites have not all succeeded is not read, and once
# they have it counts only what came after them. One whose prerequisite failed or could not be followed is skipped.
# A step waits only for steps before it, so the order can never loop.
module Chat::Watch::Step::Order
  extend ActiveSupport::Concern

  # A run started by the step it waits for may show a start a little before that step's own, by the providers' clocks.
  CLOCK_SLACK = 1.minute
  # How far back a logs step looks for the sources that were already logging when what it waits for began.
  SOURCES_BEFORE = 10.minutes
  SOURCES_LIMIT = 200
  SOURCES_SHOWN = 10

  included do
    validate :waits_only_for_earlier_steps
  end

  class_methods do
    # The positions a step at index waits for, from the labels or numbers counting from 1 Halon gave, among labels by
    # position. Answers [positions, nil], or [nil, why not] as a sentence.
    def prerequisites_named(label, refs, labels, index)
      positions = Array(refs).map do |ref|
        found = position_named(ref, labels)
        return [ nil, "#{label} waits for #{ref}, which is not one of its steps." ] if found.nil?
        return [ nil, "#{label} waits for itself, and a step waits only for steps before it." ] if found == index
        return [ nil, "#{label} waits for #{ref}, which comes after it. A step waits only for steps before it." ] if found > index

        found
      end
      [ positions.uniq.sort, nil ]
    end

    def position_named(ref, labels)
      words = ref.to_s.strip
      return if words.empty?

      by_label = labels.index { |label| label.to_s.casecmp?(words) }
      return by_label if by_label

      words.match?(/\A\d+\z/) && words.to_i.between?(1, labels.size) ? words.to_i - 1 : nil
    end

    # The sources the lines of a log reading come from, in the shared shape of a log line.
    def log_sources(text) = text.to_s.lines.filter_map { |line| line[Integrations::Telemetry::SHARED_LINE, 1] }.uniq
  end

  def waits? = waits_for.any?

  # The steps it waits for, as the watch holds them.
  def prerequisites = waits? ? watch.steps.select { |step| waits_for.include?(step.position) } : []

  # Every step it waits for succeeded, so it is read.
  def ready? = prerequisites.all? { |step| step.status == Chat::Watch::Step::STATUS_SUCCEEDED }

  # The steps it still waits for.
  def waiting_on = prerequisites.reject(&:over?)

  # A step it waits for that ended without succeeding, which skips it.
  def blocked_by = prerequisites.find { |step| step.over? && step.status != Chat::Watch::Step::STATUS_SUCCEEDED }

  # When the last of its prerequisites finished, which is where its logs are read from. Nil when it waits for nothing.
  def counts_from = prerequisites.filter_map(&:finished_at).max

  # When the last of its prerequisites began, so a run, a deploy or a container made by them counts and an older one does not.
  def runs_from = prerequisites.filter_map { |step| step.started_at || step.finished_at }.max

  # Such as "Waiting for GitHub release run and Web deploy."
  def prerequisites_words = "Waiting for #{waiting_on.map(&:label).to_sentence}."

  # Why it is skipped, naming the step that went wrong first, so a skip down a chain names the same failure.
  def skip_words(blocker)
    case blocker.status
    when Chat::Watch::Step::STATUS_FAILED then "Skipped because #{blocker.label} failed."
    when Chat::Watch::Step::STATUS_SKIPPED then blocker.reason.presence || "Skipped because #{blocker.label} was skipped."
    else "Skipped because #{blocker.label} could not be followed."
    end
  end

  # Skipped rather than read, since what it waits for went wrong. True once, for whoever saw it first.
  def skipped!(reason) = finished!(Chat::Watch::Step::STATUS_SKIPPED, reason: reason)

  # What only came after its prerequisites counts, said to whoever judges its readings. Nil when it waits for nothing.
  def order_question
    return unless waits? && counts_from

    began = clock_of(runs_from || counts_from)
    names = prerequisites.map(&:label).to_sentence
    sources = Array(sources_before).first(SOURCES_SHOWN)
    [ "It waits for #{names}, which began at #{began} and finished at #{clock_of(counts_from)}, so only what came after counts: " \
      "containers, instances, deploys or runs created after #{began}, and lines logged from #{clock_of(counts_from)} on. Anything older, " \
      "such as a container the rollout stopped, is from before and counts neither as done nor as failed.",
      ("These sources were already logging before #{names} began: #{sources.join(', ')}. Where a source names an instance or a " \
       "container, its lines are the old one's and count neither as done nor as failed." if sources.any?) ].compact.join(" ")
  end

  # The sources a logs step found already logging before its prerequisites began. True once, for whoever read them first.
  def sources_before!(sources)
    moved = self.class.where(id: id, sources_before: nil).update_all(sources_before: Array(sources).first(SOURCES_LIMIT), updated_at: Time.current)
    reload
    moved == 1
  end

  private

  def clock_of(time) = time.utc.strftime("%H:%M:%S UTC")

  def waits_only_for_earlier_steps
    return if waits_for.all? { |each| each.is_a?(Integer) && each >= 0 && each < position.to_i }

    errors.add(:waits_for, "can only name steps before it")
  end
end

# Orders changes by how likely each is to have caused what started at a given time, and says why, so the order can
# be argued with. It weighs evidence the way an engineer does: touching the failing code first, then being in the place
# the alert names, then being the kind of change that breaks things, then being close before the start.
class CodeChange::Ranking
  Change = Data.define(:repository, :kind, :sha, :at, :title, :author, :url, :pull_number, :files, :environment, :rollback)
  Suspect = Data.define(:change, :score, :reasons)

  KIND_DEPLOY = "deploy".freeze
  KIND_MERGE = "merge".freeze

  WEIGHT_TOUCHES_FAILING_CODE = 50
  WEIGHT_NAMED_PLACE = 20
  WEIGHT_RISKY_KIND = 15
  WEIGHT_DEPLOYED = 10
  WEIGHT_CLOSE = 10
  RISKY_KINDS = [ CodeChange::KIND_MIGRATION, CodeChange::KIND_CONFIG, CodeChange::KIND_FEATURE_FLAG,
                  CodeChange::KIND_DEPENDENCY, CodeChange::KIND_INFRASTRUCTURE ].freeze

  # paths are file paths from stack frames, places are repository names or service names the clues mention.
  def initialize(started:, window:, paths: [], places: [])
    @started = started
    @window = window
    @paths = paths.map(&:to_s)
    @places = places.map { |place| place.to_s.downcase }.compact_blank
  end

  # Changes after the start cannot have caused it, so they are left to the caller to show apart.
  def rank(changes)
    changes.select { |change| change.at <= @started }
           .map { |change| suspect(change) }
           .sort_by { |suspect| [ -suspect.score, -suspect.change.at.to_i ] }
  end

  private

  def suspect(change)
    reasons = []
    score = 0
    touched = touched_failing_files(change)
    if touched.any?
      score += WEIGHT_TOUCHES_FAILING_CODE
      reasons << "changes #{touched.first(3).join(', ')}, which the stack trace runs through"
    end
    if named_place?(change)
      score += WEIGHT_NAMED_PLACE
      reasons << "is in #{change.repository}, which the clues name"
    end
    risky = risky_kinds(change)
    if risky.any?
      score += WEIGHT_RISKY_KIND
      reasons << "changes #{risky.map { |kind| CodeChange::KIND_LABELS.fetch(kind).downcase }.join(' and ')}"
    end
    if change.kind == KIND_DEPLOY
      score += WEIGHT_DEPLOYED
      reasons << (change.rollback ? "is a rollback to an older commit" : "was deployed to #{change.environment}")
    else
      reasons << "was merged, which is not proof it was deployed"
    end
    minutes = ((@started - change.at) / 60).round
    closeness = [ 1 - ((@started - change.at) / @window.to_f), 0 ].max
    score += (WEIGHT_CLOSE * closeness).round
    reasons << "happened #{minutes} minutes before it started"

    Suspect.new(change: change, score: score, reasons: reasons)
  end

  # A frame's path may carry a prefix the repository does not, such as /app/ in a container, so a suffix match counts.
  def touched_failing_files(change)
    Array(change.files).select { |file| @paths.any? { |path| path == file || path.end_with?("/#{file}") || file.end_with?("/#{path}") } }
  end

  def named_place?(change)
    repository = change.repository.to_s.downcase
    short = repository.split("/").last
    @places.any? { |place| place == repository || place == short || short.include?(place) || place.include?(short) }
  end

  def risky_kinds(change)
    Array(change.files).map { |file| CodeChange.kind_for(file) }.uniq & RISKY_KINDS
  end
end

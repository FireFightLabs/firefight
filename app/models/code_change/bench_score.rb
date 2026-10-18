# How close a diff a coding agent wrote is to a code fix scenario's known right one, each score from 0 to 1. files is
# how far the files it changed are the ones the fix changes. lines is how far the lines it added and removed are the
# fix's, as the balance of what it got right against what it missed and what it added beside them, compared without
# the space around them. extra marks down every file the fix does not need. total is their mean. notes say what took
# marks away, by file.
class CodeChange::BenchScore
  NOTHING_CHANGED = "The diff changes nothing.".freeze

  Score = Data.define(:files, :lines, :extra, :total, :notes)

  def self.of(bench_case, diff_text) = new(bench_case, CodeChange::UnifiedDiff.parse(diff_text)).score

  def initialize(bench_case, produced)
    @expected = bench_case.expected
    @produced = produced
  end

  def score
    return Score.new(files: 0.0, lines: 0.0, extra: 0.0, total: 0.0, notes: [ NOTHING_CHANGED ]) if @produced.empty?

    files = (wanted & made).size.fdiv((wanted | made).size)
    extra = 1 - stray.size.fdiv(made.size)
    lines = line_score
    Score.new(files: files.round(3), lines: lines.round(3), extra: extra.round(3), total: [ files, lines, extra ].sum.fdiv(3).round(3), notes: notes)
  end

  private

  def wanted = @expected.keys

  def made = @produced.keys

  def stray = made - wanted

  def line_score
    right = wanted.sum { |path| matched(path) }
    expected_count = wanted.sum { |path| changes(@expected, path).size }
    produced_count = made.sum { |path| changes(@produced, path).size }
    return 0.0 if right.zero?

    precision = right.fdiv(produced_count)
    recall = right.fdiv(expected_count)
    2 * precision * recall / (precision + recall)
  end

  # The added and removed lines of one file, without the space around them, blank ones left out since they decide nothing.
  def changes(patches, path)
    Array(patches[path]&.changed).filter_map { |kind, text| [ kind, text.squish ] unless text.strip.empty? }
  end

  def matched(path)
    made_here = changes(@produced, path).tally
    changes(@expected, path).tally.sum { |line, count| [ count, made_here.fetch(line, 0) ].min }
  end

  def notes
    missed = (wanted - made).map { |path| "It did not change #{path}, which the fix changes." }
    short = (wanted & made).filter_map do |path|
      gap = changes(@expected, path).size - matched(path)
      "#{gap} #{'line'.pluralize(gap)} of the expected change #{gap == 1 ? 'is' : 'are'} missing in #{path}." if gap.positive?
    end
    beside = (wanted & made).filter_map do |path|
      over = changes(@produced, path).size - matched(path)
      "#{over} #{'line'.pluralize(over)} in #{path} #{over == 1 ? 'is' : 'are'} not part of the fix." if over.positive?
    end
    missed + short + beside + stray.map { |path| "It changed #{path}, which the fix does not need." }
  end
end

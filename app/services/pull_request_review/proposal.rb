# A finding as the reviewer reported it, read and checked for what it needs before anything verifies it: its labels,
# a failure chain and evidence Firefight can open. Each piece of evidence is resolved to a link: an incident or its
# postmortem in this workspace, a resource on the map the reviewer may read, code at the pull request's head, or a
# metric's link that a result the review read gave. Evidence that resolves to nothing is dropped and said, and a report
# left with none is refused.
class PullRequestReview::Proposal
  CODE_REFERENCE = /\A(?<path>[^:\s][^:]*?)(?::(?<line>\d+)(?:-\d+)?)?\z/
  LINK = %r{\Ahttps?://\S+\z}

  attr_reader :attributes, :dropped

  # The reported finding read into a proposal, or the reason it is refused.
  def self.read(arguments, runner)
    proposal = new(arguments, runner)
    refusal = proposal.refusal
    refusal ? [ nil, refusal ] : [ proposal, nil ]
  end

  def initialize(arguments, runner)
    @arguments = arguments
    @runner = runner
    @dropped = []
    @attributes = build
  end

  def path = attributes[:path]
  def line = attributes[:line]
  def claim = attributes[:claim]

  def refusal
    problems = []
    problems << "category must be one of #{PullRequestReview::Finding::CATEGORIES.join(', ')}." unless PullRequestReview::Finding::CATEGORIES.include?(attributes[:category])
    problems << "severity must be one of #{PullRequestReview::Finding::SEVERITIES.join(', ')}." unless PullRequestReview::Finding::SEVERITIES.include?(attributes[:severity])
    problems << "effort must be one of #{PullRequestReview::Finding::EFFORTS.join(', ')}." unless PullRequestReview::Finding::EFFORTS.include?(attributes[:effort])
    problems << "claim and why are needed." if claim.blank? || attributes[:why].blank?
    problems << "failure_chain needs at least one step." if attributes[:failure_chain].empty?
    problems << "There is no file #{path} at the pull request's head or in its diff." unless @runner.known_path?(path)
    problems << "No evidence resolved. #{@dropped.join(' ')}".strip if attributes[:evidence].empty?
    "Not reported. #{problems.join(' ')}" if problems.any?
  end

  # The finding as the check reads it, labels first.
  def text
    chain = attributes[:failure_chain].each_with_index.map { |step, index| "#{index + 1}. #{step}" }.join("\n")
    evidence = attributes[:evidence].map { |item| "- #{item['kind']}: #{item['title']} (#{item['url']})" }.join("\n")
    [
      "#{PullRequestReview::Finding::CATEGORY_LABELS.fetch(attributes[:category])} | #{attributes[:severity].capitalize} | " \
      "#{PullRequestReview::Finding::EFFORT_LABELS.fetch(attributes[:effort])}#{' | serious' if attributes[:serious]}",
      "Where: #{path}#{":#{line}" if line}",
      "Claim: #{claim}", "Why: #{attributes[:why]}", "Failure chain:\n#{chain}", "Evidence:\n#{evidence}",
      ("Suggested fix:\n#{attributes[:suggested_fix]}" if attributes[:suggested_fix].present?),
      ("Lesson from #{lesson.source.identifier}: #{lesson.text}" if lesson)
    ].compact.join("\n")
  end

  # The approved lesson the finding comes from, when the reviewer named one it was handed.
  def lesson = (@lesson ||= @runner.lesson_cited(@arguments["lesson"]) if @arguments["lesson"].present?)

  private

  def build
    path = @arguments["path"].to_s.strip.delete_prefix("/")
    {
      path: path, line: Integer(@arguments["line"].to_s, exception: false)&.then { |number| number if number.positive? },
      category: @arguments["category"].to_s, severity: @arguments["severity"].to_s, effort: @arguments["effort"].to_s,
      serious: @arguments["serious"] == true, claim: @arguments["claim"].to_s.squish, why: @arguments["why"].to_s.strip,
      failure_chain: Array(@arguments["failure_chain"]).map { |step| step.to_s.squish }.compact_blank,
      evidence: Array(@arguments["evidence"]).filter_map { |item| resolved(item) if item.is_a?(Hash) },
      suggested_fix: @arguments["suggested_fix"].to_s.strip.presence, agent_instructions: @arguments["agent_instructions"].to_s.strip.presence,
      lesson_id: cited_lesson_id
    }
  end

  # A lesson id that is not one of those listed names none, and is said, so the finding is still checked on its own.
  def cited_lesson_id
    return nil if @arguments["lesson"].blank?
    return lesson.id if lesson

    @dropped << "The lesson #{@arguments['lesson'].to_s.inspect} is not one of the approved lessons listed, so the finding names none."
    nil
  end

  def resolved(item)
    kind = item["kind"].to_s
    reference = item["reference"].to_s.strip
    title = item["title"].to_s.squish
    url = case kind
    when PullRequestReview::Finding::EVIDENCE_INCIDENT then @runner.incident_link(reference)
    when PullRequestReview::Finding::EVIDENCE_POSTMORTEM then @runner.postmortem_link(reference)
    when PullRequestReview::Finding::EVIDENCE_MAP_RESOURCE then @runner.resource_link(reference)
    when PullRequestReview::Finding::EVIDENCE_METRIC then (reference if reference.match?(LINK) && @runner.read?(reference))
    when PullRequestReview::Finding::EVIDENCE_CODE then code_link(reference)
    end
    unless url && title.present?
      @dropped << "The #{kind.presence || 'unnamed'} evidence #{reference.inspect} points at nothing Firefight can open#{', or has no title' if url}."
      return nil
    end

    { "kind" => kind, "title" => title, "url" => url }
  end

  def code_link(reference)
    found = reference.match(CODE_REFERENCE)
    return unless found && @runner.known_path?(found[:path])

    @runner.file_link(found[:path], found[:line]&.to_i)
  end
end

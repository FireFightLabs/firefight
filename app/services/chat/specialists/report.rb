# The one way a specialist reports: findings, each with the lines that show it and the links its results gave, the
# changes it would make, and what it could not check. Halon cites the lines and links, so each is checked against what
# the specialist really read, and a change must be one of its kind's (Chat::Specialists::Live#changes) with the reads
# behind it named. A report that fails a check is refused with why, so the specialist fixes it before it ends.
class Chat::Specialists::Report < RubyLLM::Tool
  NAME = Chat::Helper::REPORT_FINDINGS
  MAX_FINDINGS = 8
  MAX_LINES = 5
  MAX_CHANGES = 3
  # What Halon reads back, per specialist. A longer report is cut here, and Halon's own chat saves anything over its model's
  # share whole for read_result (Chat::Tools.hand_over).
  LIMIT = Chat::Helper::SPECIALIST_REPORT_LIMIT
  LINK = %r{\Ahttps?://\S+\z}

  Finding = Data.define(:claim, :lines, :links)

  def initialize(chat, changes:)
    super()
    @chat = chat
    @changes = changes
    @report = nil
  end

  def name = NAME

  def description
    "Report what you found, once, last. Each finding is one claim with the exact lines from your results that show it and " \
      "the links those results gave. A change you would make is the exact tool, its arguments and the reads behind it."
  end

  def parameters_schema
    properties = {
      "summary" => { "type" => "string", "description" => "The answer to the objective in one or two sentences" },
      "findings" => {
        "type" => "array", "maxItems" => MAX_FINDINGS,
        "items" => {
          "type" => "object",
          "properties" => {
            "claim" => { "type" => "string", "description" => "What you found, in one sentence" },
            "lines" => { "type" => "array", "items" => { "type" => "string" }, "minItems" => 1, "maxItems" => MAX_LINES,
                         "description" => "Lines copied exactly from your results that show it" },
            "links" => { "type" => "array", "items" => { "type" => "string" },
                         "description" => "Links your results gave for it, such as a deployment's or a dashboard's page (optional)" }
          },
          "required" => [ "claim", "lines" ]
        }
      },
      "not_checked" => { "type" => "array", "items" => { "type" => "string" }, "description" => "What you could not check, and why (optional)" }
    }
    properties["proposed_changes"] = proposed_changes if @changes.any?
    { "type" => "object", "properties" => properties, "required" => [ "summary", "findings" ] }
  end

  def taken? = !@report.nil?

  # The arguments match the schema above, not an execute signature, so skip the base check.
  def call(tool_call: nil, **arguments)
    given = arguments.deep_stringify_keys
    findings = Array(given["findings"]).first(MAX_FINDINGS).map do |finding|
      Finding.new(claim: finding["claim"].to_s.squish, lines: Array(finding["lines"]).map(&:to_s).map(&:strip).compact_blank.first(MAX_LINES),
                  links: Array(finding["links"]).map(&:to_s).map(&:strip).compact_blank)
    end
    proposals = Array(given["proposed_changes"]).first(MAX_CHANGES).map { |change| Chat::Specialists::Proposal.from(change) }
    refused = refusal(findings, proposals)
    return refused if refused

    @report = { summary: given["summary"].to_s.squish, findings: findings, proposals: proposals,
                not_checked: Array(given["not_checked"]).map(&:to_s).compact_blank }
    "Reported."
  end

  # What Halon reads, in plain lines.
  def text
    return unless @report

    lines = [ @report[:summary] ]
    @report[:findings].each_with_index do |finding, index|
      lines << "#{index + 1}. #{finding.claim}"
      finding.lines.each { |line| lines << "   Shows: #{line}" }
      finding.links.each { |link| lines << "   Link: #{link}" }
    end
    @report[:proposals].each do |proposal|
      lines << "Proposed change: #{proposal.tool} #{proposal.arguments.to_json}"
      proposal.because.each { |read| lines << "   Because #{read}" }
      lines << "   Undo: #{proposal.undo}" if proposal.undo
    end
    @report[:not_checked].each { |gap| lines << "Not checked: #{gap}" }
    lines.join("\n").truncate(LIMIT)
  end

  def proposals = @report ? @report[:proposals] : []

  private

  def proposed_changes
    {
      "type" => "array", "maxItems" => MAX_CHANGES, "description" => "Changes you would make, which Halon decides on (optional)",
      "items" => {
        "type" => "object",
        "properties" => {
          "tool" => { "type" => "string", "enum" => @changes.map(&:name), "description" => "The tool that makes it" },
          "arguments" => { "type" => "object", "description" => "Its arguments, as the tool takes them" },
          "because" => { "type" => "array", "items" => { "type" => "string" }, "minItems" => 1,
                         "description" => "Each read that shows it will help, by the tool you called then what it showed, such as \"search_logs: worker boots with pool 40 since 13:38\"" },
          "undo" => { "type" => "string", "description" => "How to undo it (optional)" }
        },
        "required" => [ "tool", "arguments", "because" ]
      }
    }
  end

  def refusal(findings, proposals)
    corpus = read_text
    flat = squished(corpus)
    called = @chat.tool_calls.where.not(name: NAME).pluck(:name).map(&:downcase).to_set
    problems = []
    findings.each do |finding|
      problems << "A finding has no lines: #{finding.claim}" if finding.lines.empty?
      finding.lines.reject { |line| flat.include?(squished(line)) }.each { |line| problems << "This line is not in anything you read, so copy it exactly: #{line}" }
      finding.links.reject { |link| link.match?(LINK) && corpus.include?(link) }.each { |link| problems << "This link is not in anything you read: #{link}" }
    end
    proposals.each do |proposal|
      problems << "#{proposal.tool} is not a change of your kind. The changes are: #{@changes.map(&:name).join(', ')}." unless @changes.any? { |change| change.name == proposal.tool }
      named = proposal.because.map { |read| read[Chat::Tools::LookFirst::NAMED].to_s.downcase }
      problems << "Name the reads behind #{proposal.tool} by the tools you called." if named.empty? || named.none? { |each| called.include?(each) }
    end
    return if problems.empty?

    "Not reported. Fix these and report again:\n#{problems.uniq.join("\n")}"
  end

  def read_text
    results = @chat.tool_calls.where.not(name: NAME).includes(:result).filter_map { |call| call.result&.content.to_s }
    (results + @chat.saved_results.reload.map(&:content)).join("\n")
  end

  def squished(text) = text.to_s.squish.downcase
end

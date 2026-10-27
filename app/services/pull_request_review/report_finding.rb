# How the reviewer reports one problem. A report missing what a finding needs, or whose evidence points at nothing
# Firefight can open, is refused with why so the reviewer fixes it. A report that holds together goes to a check of its
# own (PullRequestReview::Verification), and the reviewer is told whether it was written, what it changed among the
# earlier findings, or why it was dropped. It runs alone, never beside another call, so findings are checked and
# written in the order reported.
class PullRequestReview::ReportFinding < RubyLLM::Tool
  NAME = "report_finding".freeze

  EVIDENCE_REFERENCES = {
    PullRequestReview::Finding::EVIDENCE_INCIDENT => "the incident's identifier, such as INC-012",
    PullRequestReview::Finding::EVIDENCE_POSTMORTEM => "the identifier of the incident it is the postmortem of",
    PullRequestReview::Finding::EVIDENCE_MAP_RESOURCE => "the resource's id on the map",
    PullRequestReview::Finding::EVIDENCE_METRIC => "the link a tool result gave for it",
    PullRequestReview::Finding::EVIDENCE_CODE => "path:line at the pull request's head, such as app/jobs/retry_job.rb:42"
  }.freeze

  def initialize(runner)
    super()
    @runner = runner
  end

  def name = NAME

  def description
    "Report one problem in the pull request, once its failure chain is shown with evidence. A separate check verifies it " \
      "before it is written, and the answer says whether it was written, what it changed among the earlier findings, or why it was dropped."
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "path" => { "type" => "string", "description" => "The file to fix, as the repository names it" },
        "line" => { "type" => "integer", "description" => "The line to fix at the pull request's head, counting from 1 (optional, none for the file as a whole)" },
        "category" => { "type" => "string", "enum" => PullRequestReview::Finding::CATEGORIES },
        "severity" => { "type" => "string", "enum" => PullRequestReview::Finding::SEVERITIES },
        "effort" => { "type" => "string", "enum" => PullRequestReview::Finding::EFFORTS },
        "serious" => { "type" => "boolean", "description" => "True when merging it as it is would likely cause an incident" },
        "claim" => { "type" => "string", "description" => "One line, written as what to do" },
        "why" => { "type" => "string", "description" => "Two to four short plain sentences naming the methods and values involved" },
        "failure_chain" => {
          "type" => "array", "items" => { "type" => "string" }, "minItems" => 1,
          "description" => "From the change to what fails in production and who notices, one short step each, in order"
        },
        "evidence" => {
          "type" => "array", "minItems" => 1,
          "items" => {
            "type" => "object",
            "properties" => {
              "kind" => { "type" => "string", "enum" => PullRequestReview::Finding::EVIDENCE_KINDS },
              "reference" => { "type" => "string", "description" => EVIDENCE_REFERENCES.map { |kind, words| "#{kind}: #{words}" }.join(". ") },
              "title" => { "type" => "string", "description" => "What it shows, in a few words" }
            },
            "required" => %w[kind reference title]
          },
          "description" => "What shows each step of the chain"
        },
        "suggested_fix" => { "type" => "string", "description" => "The change itself, as a short diff or code (optional)" },
        "lesson" => { "type" => "string", "description" => "The id of the approved lesson from a past incident this finding comes from, as the facts list it (optional)" },
        "agent_instructions" => { "type" => "string", "description" => "The same finding as steps a coding agent can follow alone" }
      },
      "required" => %w[path category severity effort serious claim why failure_chain evidence agent_instructions]
    }
  end

  # The arguments match the schema above, not an execute signature, so skip the base check.
  def call(tool_call: nil, **arguments)
    @runner.report(arguments.deep_stringify_keys)
  end
end

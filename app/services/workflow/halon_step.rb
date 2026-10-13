# The two steps that hand work to Halon: judging data it is given (Ask Halon) and following one skill with only its
# tools (Run a skill). Each runs as whoever the run acts as, under the run's AI ceiling, on a chat of the step's own,
# and its answer goes back to the step as fields a later step can read.
class Workflow::HalonStep
  KEY_ERROR = "error".freeze
  VERDICT = "verdict".freeze
  SUMMARY = "summary".freeze
  SEVERITY = "severity".freeze
  FINDINGS = "findings".freeze
  OUT_OF_ROOM = "This run spent its AI ceiling, so Halon did not run this step.".freeze

  def initialize(run, record)
    @run = run
    @record = record
    @workspace = run.workspace
  end

  # Judges the data. fields are [name, description] pairs.
  def ask!(question:, data:, fields:)
    refused = refusal
    return { KEY_ERROR => refused } if refused

    answer = FirefightAi::WorkflowAnswer.new(@workspace, inferable: @run).answer(question: question, data: shown(data), fields: fields)
    { VERDICT => answer.verdict, SUMMARY => answer.summary }.merge(answer.fields)
  end

  # Follows the skill with only the tools it names that whoever the run acts as may read with, and reports.
  def follow!(skill_name:, focus:)
    refused = refusal
    return { KEY_ERROR => refused } if refused

    skill = Chat::Skill.available_to(@workspace).find { |each| each.name == skill_name.to_s }
    return { KEY_ERROR => "There is no skill called #{skill_name} for this workspace's connections." } unless skill

    follower = FirefightAi::SkillFollower.new(@workspace, inferable: @run)
    chat = Chat.find_by(owner: @record) || Chat.open!(owner: @record, workspace: @workspace, model_choice: follower.ai_model)
    agent_run = Workflow::AgentRun.new(run: @run, record: @record, chat: chat, reads_only: true)
    in_hand = []
    steps = Chat::Tools::UseSkill.new(agent_run, offer: ->(tools) { in_hand.concat(tools) }).call(skill: skill.name)
    chat.add_message(role: Chat::Message::ROLE_USER, content: question(skill, focus))
    report = Report.new
    follower.run(chat: chat, tools: [ Chat::Tools::ReadResult.new(agent_run), report, *in_hand ], skill_text: steps,
                 max_spend_cents: room_cents, answered: -> { report.report.present? })
    report.report || { KEY_ERROR => "Halon followed #{skill.name} but did not report what it found." }
  end

  private

  def refusal
    Investigation.unavailable_reason(@workspace) || (OUT_OF_ROOM if room_cents <= 0)
  end

  # What is left of the run's ceiling, else of what one chat may spend in this workspace.
  def room_cents
    limit = @workspace.conversation_limits.max_spend_cents
    cap = @run.workflow.cost_cap_cents
    return limit unless cap

    [ cap - @run.ai_spent_cents, limit ].min
  end

  def shown(data) = data.is_a?(String) ? data : JSON.pretty_generate(data)

  def question(skill, focus)
    [ "Follow #{skill.name} for the workflow #{@run.workflow.name}.", focus.to_s.strip.presence&.then { |words| "What to look at: #{words}" },
      "When you are done, call report_step once." ].compact.join("\n\n")
  end

  # The one way a skill step ends.
  class Report < RubyLLM::Tool
    NAME = "report_step".freeze
    SEVERITIES = Investigation::Notice::SEVERITIES

    description "Report what you found for this step, once, last."
    parameter :verdict, description: "One of: #{FirefightAi::Schemas::WorkflowAnswer::VERDICTS.join(', ')}"
    parameter :summary, description: "Two or three plain sentences on what you looked at and found"
    parameter :severity, description: "For a problem, one of: #{SEVERITIES.join(', ')}", required: false
    parameter :findings, type: "array", description: "Each thing you found, one plain sentence each, naming what showed it", required: false

    attr_reader :report

    def name = NAME

    def execute(verdict:, summary:, severity: nil, findings: [])
      verdict = FirefightAi::Schemas::WorkflowAnswer::VERDICTS.include?(verdict.to_s) ? verdict.to_s : FirefightAi::Schemas::WorkflowAnswer::UNSURE
      @report = { VERDICT => verdict, SUMMARY => summary.to_s.strip, SEVERITY => (severity.to_s if SEVERITIES.include?(severity.to_s)),
                  FINDINGS => Array(findings).map { |finding| finding.to_s.strip }.compact_blank }
      "Reported."
    end
  end
end

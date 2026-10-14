# The two steps that hand work to Halon: judging data it is given (Ask Halon) and following one skill with only its
# tools (Run a skill). Each runs as whoever the run acts as, under the run's spending ceiling, on a chat of the step's own,
# and its answer goes back to the step as fields a later step can read.
class Workflow::HalonStep
  KEY_ERROR = "error".freeze
  VERDICT = "verdict".freeze
  SUMMARY = "summary".freeze
  SEVERITY = "severity".freeze
  FINDINGS = "findings".freeze
  # Each problem that needs a person, with what a notice of it holds, so a later step can raise one notice for each.
  PROBLEMS = "problems".freeze
  PROBLEM_FIELDS = %w[topic summary severity resource due_on].freeze
  OUT_OF_ROOM = "This run reached its spending ceiling, so Halon did not run this step.".freeze

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

    off = Chat::CustomSkill.off_reason(@workspace, skill_name)
    return { KEY_ERROR => off } if off

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

  # What is left of the run's spending ceiling, its sandbox time counted with its AI, else of what one chat may spend in
  # this workspace.
  def room_cents = @room_cents ||= @run.room_cents(@workspace.conversation_limits.max_spend_cents)

  def shown(data) = data.is_a?(String) ? data : JSON.pretty_generate(data)

  def question(skill, focus)
    [ "Follow #{skill.name} for the workflow #{@run.workflow.name}.", focus.to_s.strip.presence&.then { |words| "What to look at: #{words}" },
      "When you are done, call report_step once." ].compact.join("\n\n")
  end

  # The one way a skill step ends.
  class Report < RubyLLM::Tool
    NAME = "report_step".freeze
    SEVERITIES = Investigation::Notice::SEVERITIES

    attr_reader :report

    def name = NAME

    def description = "Report what you found for this step, once, last."

    def parameters_schema
      {
        "type" => "object",
        "properties" => {
          "verdict" => { "type" => "string", "enum" => FirefightAi::Schemas::WorkflowAnswer::VERDICTS },
          "summary" => { "type" => "string", "description" => "Two or three plain sentences on what you looked at and found" },
          "severity" => { "type" => "string", "enum" => SEVERITIES, "description" => "For a problem, how much it matters" },
          "findings" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Each thing you found, one plain sentence each, naming what showed it" },
          "problems" => {
            "type" => "array",
            "description" => "Each problem that needs a person, one each, so each is told once and again only when it gets worse",
            "items" => {
              "type" => "object",
              "properties" => {
                "topic" => { "type" => "string", "description" => "What it is about in a few words, the same each time for the same problem, such as the data volume of orders-db" },
                "summary" => { "type" => "string", "description" => "What is happening and by when, in one or two plain sentences a team reads in a channel" },
                "severity" => { "type" => "string", "enum" => SEVERITIES },
                "resource" => { "type" => "string", "description" => "The resource on the map it is about, by its id or name, when it is about one" },
                "due_on" => { "type" => "string", "description" => "The day it becomes a problem, as YYYY-MM-DD, when there is one" }
              },
              "required" => %w[topic summary severity]
            }
          }
        },
        "required" => %w[verdict summary]
      }
    end

    # The arguments match the schema above, not an execute signature, so the base check is skipped. They arrive keyed by
    # text, as the model sent them.
    def call(tool_call: nil, **arguments)
      given = arguments.stringify_keys
      verdict = FirefightAi::Schemas::WorkflowAnswer::VERDICTS.include?(given["verdict"].to_s) ? given["verdict"].to_s : FirefightAi::Schemas::WorkflowAnswer::UNSURE
      @report = { VERDICT => verdict, SUMMARY => given["summary"].to_s.strip, SEVERITY => (given["severity"].to_s if SEVERITIES.include?(given["severity"].to_s)),
                  FINDINGS => Array(given["findings"]).map { |finding| finding.to_s.strip }.compact_blank,
                  PROBLEMS => Report.problems_of(given["problems"]) }
      "Reported."
    end

    # Each problem with a topic and a summary, its fields as text, its severity one Firefight knows and its day a date,
    # dropped when it is not one, since a raise_notice step refuses a day it cannot read and the notice would be lost.
    def self.problems_of(given)
      Array(given).filter_map do |problem|
        next unless problem.is_a?(Hash)

        kept = problem.stringify_keys.slice(*PROBLEM_FIELDS).transform_values { |value| value.to_s.strip }
        next if kept["topic"].blank? || kept["summary"].blank?

        kept.merge("severity" => kept["severity"].presence_in(SEVERITIES) || Investigation::Notice::SEVERITY_LOW, "due_on" => day_of(kept["due_on"])).compact_blank
      end
    end

    def self.day_of(text)
      Date.iso8601(text).iso8601 if text.present?
    rescue Date::Error
      nil
    end
  end
end

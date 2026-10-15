class Investigation::Tools::Conclude < RubyLLM::Tool
  # The class is namespaced, the model sees the plain name the prompt asks for.
  def self.tool_name = "conclude"

  def initialize(investigation)
    super()
    @investigation = investigation
  end

  def name = self.class.tool_name

  def description
    "Finish the investigation with the answer the evidence supports. Nothing else ends a run. " \
      "Every line of evidence is a claim and the step numbers it rests on, and one that cites no real step is refused. " \
      "The first conclude asks you to try to prove the answer wrong before it is recorded, and each claim is then read " \
      "against the steps it cites. When the evidence supports no cause, conclude saying so, with what you could not check."
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "summary" => { "type" => "string", "description" => "What happened and why, in a few sentences, using only what the evidence shows. A chart's marker goes on a line of its own after the sentence about what it shows" },
        "hypothesis" => { "type" => "string", "description" => "The assertion of the theory the evidence supports, exactly as recorded, or leave out when none holds" },
        "evidence" => {
          "type" => "array", "description" => "What the answer rests on, one item per claim",
          "items" => {
            "type" => "object",
            "properties" => {
              "claim" => { "type" => "string", "description" => "One thing the evidence shows, in a sentence" },
              "steps" => { "type" => "array", "items" => { "type" => "integer" }, "description" => "The step numbers of the tool results that show it" }
            },
            "required" => %w[claim steps]
          }
        },
        "gaps" => { "type" => "string", "description" => "What you could not check, and why it matters" },
        "fix" => {
          "type" => "object",
          "description" => "How to fix what you found. Required when you name a cause. Give it even when nothing here can apply it, " \
                           "so a person has the steps. When what you would change is defined as code, such as Terraform, " \
                           "Pulumi, Helm or a manifest (the map says where a resource is managed in code), the fix is a " \
                           "pull_request to that code, since the next apply would undo a direct change",
          "properties" => {
            "summary" => { "type" => "string", "description" => "What the fix changes and why it fixes the cause, in a sentence or two" },
            "verify" => { "type" => "string", "description" => "How to tell it worked: the signal to watch and the level it should return to, " \
                                                               "such as 5xx back under its usual rate" },
            "steps" => {
              "type" => "array", "description" => "In the order they should run",
              "items" => {
                "type" => "object",
                "properties" => {
                  "kind" => { "type" => "string", "enum" => Investigation::RemediationStep::KINDS,
                              "description" => "pull_request for a code change in one repository, action for a change through one of the " \
                                               "workspace's tools (acting on a pull request or an issue without changing code, such as " \
                                               "closing one or rerunning a workflow, is an action through the code host's own tool), " \
                                               "manual for anything Firefight cannot do, page_check (optional, last) to confirm in " \
                                               "Halon's browser that a page people use works once the steps before it ran" },
                  "description" => { "type" => "string", "description" => "What this step changes, in a sentence. For a change to another " \
                                                                          "system's interface, such as a webhook, an API, a config format or a " \
                                                                          "CI trigger, cite its documented contract and its live setup as you " \
                                                                          "read them, and say what you could not verify" },
                  "repository" => { "type" => "string", "description" => "For pull_request: the repository, as owner/name" },
                  "tool" => { "type" => "string", "description" => "For action: the tool's name, as you call it" },
                  "arguments" => { "type" => "object", "description" => "For action: the arguments to call it with. For page_check: url, " \
                                                                         "and optionally steps and viewports, as #{Chat::BrowserCheck::TOOL_NAME} takes them" },
                  "missing" => { "type" => "string", "description" => "For manual: what Firefight would need to do it, such as a tool to switch on" },
                  "undo" => { "type" => "string", "description" => "How to put it back if it makes things worse" },
                  "depends_on" => { "type" => "array", "items" => { "type" => "integer" }, "description" => "Earlier step numbers that must finish first" }
                },
                "required" => %w[kind description]
              }
            }
          },
          "required" => %w[summary steps]
        },
        "suggest_incident" => {
          "type" => "boolean",
          "description" => "Only when there is no incident yet: true when what you found is hurting users now and the team should declare one"
        },
        "page" => {
          "type" => "object",
          "description" => "Only when the facts' on_call says pages_on_call: who is on call now for what broke, whom Firefight pages with " \
                           "your answer. With paging_tools in on_call, the page is raised in that tool on target. Leave it out otherwise",
          "properties" => {
            "person" => { "type" => "string", "description" => "Their email, as the on-call tool gave it" },
            "steps" => { "type" => "array", "items" => { "type" => "integer" }, "description" => "The step numbers of the results that show they are on call" },
            "tool" => { "type" => "string", "description" => "The paging tool to raise the page in, by its tool name in on_call's paging_tools. Needed only when there are several" },
            "target" => { "type" => "string", "description" => "What to page in that tool, as its pages field says, such as the service whose escalation policy has them on call" }
          },
          "required" => %w[person steps]
        }
      },
      "required" => [ "summary" ]
    }
  end

  # The arguments match the schema above, not an execute signature, so skip the base check.
  # They arrive keyed by text, as the model sent them.
  # The first answer is argued with before it is recorded, unless the budget has no room left for that.
  def call(tool_call: nil, **arguments)
    return critique if !@investigation.budget_spent? && @investigation.ask_for_critique!

    asked = arguments.symbolize_keys
    check_fix!(asked)
    page = @investigation.page_to(asked[:page]) if asked[:page].present?
    evidence = Array(asked[:evidence])
    evidence.each_with_index { |item, index| @investigation.cited_steps!(item.to_h.stringify_keys["steps"], what: "Evidence #{index + 1}") }
    reread = Investigation::Rereading.new(@investigation).check(evidence)
    refuse_emptied_cause!(asked[:hypothesis], reread)

    @investigation.conclude!(
      summary: asked[:summary], hypothesis_assertion: asked[:hypothesis], evidence: reread.kept, gaps: asked[:gaps],
      suggest_incident: asked[:suggest_incident] == true, fix: asked[:fix], page: page
    )
    "Answer recorded. The run is over."
  rescue Investigation::Evidence::Refused, Investigation::RemediationPlan::Refused, Investigation::PageRefused => refused
    { error: refused.message }
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
    { error: error.message }
  end

  # Theories still open are named with the critique, so they are tested at once with helpers or said to be open.
  OPEN_THEORIES = "Theories still open: %<open>s. Test them at once with run_helpers and record what each shows, or say in " \
                  "the summary and gaps that they are still open and what would settle them.".freeze

  private

  def critique
    open = @investigation.hypotheses.where(status: Investigation::Hypothesis::STATUS_OPEN).pluck(:assertion)
    return FirefightAi::Investigator::CRITIQUE if open.empty?

    "#{FirefightAi::Investigator::CRITIQUE} #{format(OPEN_THEORIES, open: open.to_sentence)}"
  end


  # Before the claims are re-read, which costs a model call, so a fix that will be refused never pays for one.
  def check_fix!(asked)
    raise Investigation::RemediationPlan::Refused, "Naming a cause needs a fix. Say how to fix it, step by step." if asked[:hypothesis].present? && asked[:fix].blank?

    Investigation::RemediationPlan.check!(@investigation.workspace, asked[:fix], principal: @investigation.acting_principal) if asked[:fix].present?
  end

  # A cause with nothing left behind it is sent back with why, so the agent can cite what shows it or name no cause.
  def refuse_emptied_cause!(hypothesis, reread)
    return if hypothesis.blank? || reread.kept.any? || reread.dropped.empty?

    why = reread.dropped.map { |dropped| "\"#{dropped.claim}\": #{dropped.reason}" }.join(" ")
    raise Investigation::Evidence::Refused,
      "Every claim was dropped when read against the steps it cites. #{why} Conclude with claims those steps show, or with no cause."
  end
end

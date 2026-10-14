# Opens a page in Halon's browser in the run's sandbox, on desktop and phone, follows a short path (go to, click, fill,
# press, wait for or expect text), and hands on how it went: status, title, timings, console errors, failed requests,
# its text and the trouble found, with a screenshot of each screen size kept on the run. It only reads. A step that
# names a send step sends what the page sends at that step, which is a change: never in a run nobody pressed, only
# after the same path stopped just before it and showed what it would send, sent exactly that, through the gateway as
# browser.update so a grant and approval rules decide it, and pretended in a test run. A page that sends anything else
# by then, another query or body included, is not sent and fails the step saying what it sends now.
class DefinedWorkflow::Steps::Browser < DefinedWorkflow::Steps::CallTool
  kind "browser"
  label "Browser"
  group GROUP_SANDBOX

  KEY_URL = "url".freeze
  KEY_STEPS = "steps".freeze
  KEY_VIEWPORTS = "viewports".freeze
  KEY_LOG_IN = "log_in".freeze
  KEY_SEND_STEP = "send_step".freeze
  CHECK_KEYS = [ KEY_URL, KEY_STEPS, KEY_VIEWPORTS, KEY_LOG_IN, KEY_SEND_STEP ].freeze
  OUTPUT_OK = "ok".freeze
  OUTPUT_TROUBLE = "trouble".freeze
  OUTPUT_STATUS = "status".freeze
  OUTPUT_TITLE = "title".freeze
  OUTPUT_FINAL_URL = "final_url".freeze
  OUTPUT_TEXT = "text".freeze
  OUTPUT_TIMINGS = "timings_ms".freeze
  OUTPUT_SCREENSHOTS = "screenshots".freeze
  OUTPUT_SENT = "sent".freeze
  OUTPUT_WOULD_SEND = "would_send".freeze
  OUTPUTS = [ OUTPUT_OK, OUTPUT_TROUBLE, OUTPUT_STATUS, OUTPUT_TITLE, OUTPUT_FINAL_URL, OUTPUT_TEXT, OUTPUT_TIMINGS, OUTPUT_SCREENSHOTS, OUTPUT_SENT,
              OUTPUT_WOULD_SEND ].freeze
  TEXT_LIMIT = 4_000
  UNAVAILABLE_WORDS = DefinedWorkflow::Steps::Sandbox::UNAVAILABLE
  UNATTENDED = "Nobody pressed Run, so nothing a page would send is sent from this run. It sends only in a run a person starts.".freeze
  NOT_STOPPED = "The page did not stop before step %<step>s to send something, so nothing was sent. Check the path.".freeze
  CHANGED = "The page now sends %<sends>s at step %<step>s, not what it showed just before, so nothing was sent.".freeze

  config_help "url, steps (each {action: goto, click, fill, press, wait_for_text or expect_text, with url, text, label, role and name, " \
              "placeholder, value or key}), viewports (desktop, phone, both by default), log_in (true to log in with the site's saved test login " \
              "first), send_step (the step number allowed to send, which makes it a change needing undo, never in a run nobody pressed). " \
              "Outputs ok, trouble, status, title, final_url, text, timings_ms, screenshots, sent and would_send."

  class << self
    def check_of(config) = Chat::BrowserCheck.from(config.slice(*CHECK_KEYS))

    def sends?(config) = config[KEY_SEND_STEP].present?

    def changes?(config, _workspace) = sends?(config)

    def checks?(config, _workspace) = !sends?(config)

    def output_fields(_config) = OUTPUTS

    def problems(step, workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      found = []
      found << "#{named} needs a sandbox, and none can be started for this workspace." unless Integrations::Terminal.available?(workspace)
      begin
        check_of(config) unless Workflow::Version.references_in(config.slice(*CHECK_KEYS)).any?
      rescue Chat::BrowserCheck::Refused => refused
        found << "#{named}: #{refused.message}"
      end
      found << "#{named} needs the address it opens." if config[KEY_URL].to_s.strip.empty?
      found + undo_problems(step, workspace)
    end

    # Looking is open to everyone. Sending needs browser.update granted.
    def reach(config, workspace)
      action = sends?(config) && Ability::Action.lookup(Ability::Action::BROWSER_SUBMIT, workspace)
      action ? [ DefinedWorkflow::Reach::Needed.of_action(action) ] : []
    end

    def describe(config, _workspace)
      sends = sends?(config) ? ", sending at step #{config[KEY_SEND_STEP]}" : ""
      "#{config[KEY_URL]}, #{Array(config[KEY_STEPS]).size} steps#{sends}".truncate(200)
    end
  end

  def tool_name = Chat::BrowserCheck::TOOL_NAME

  def arguments = @config.slice(*CHECK_KEYS)

  # A send never happens in a run nobody pressed (call refuses it), so there is nothing to read first.
  def read_first(*, **) = nil


  private

  def check = @check ||= self.class.check_of(@config)

  # Reads the page, or, for a step that sends, looks first, stopping before the send, then sends exactly what it saw.
  def call(approval_id)
    raise Refused, UNAVAILABLE_WORDS unless Integrations::Terminal.available?(workspace)
    return output_of_answer(browse(look_only, Ability::Action::BROWSER_READ), sent: false) unless check.sends?
    raise Refused, UNATTENDED if @run.reads_first?

    looked = browse(look_only(sending: true), Ability::Action::BROWSER_READ, keep: false)
    stopped = looked.viewports.find { |viewport| viewport.dig("stopped", "step").to_i == check.send_step && viewport.dig("stopped", "would_send").present? }
    raise Refused, format(NOT_STOPPED, step: check.send_step) unless stopped

    shown = stopped.dig("stopped", "would_send").to_h
    sent = browse(check, Ability::Action::BROWSER_SUBMIT, approval_id: approval_id, expected_send: shown.slice(*Chat::BrowserCheck::SEND_KEYS))
    changed = sent.changed_request
    raise Refused, format(CHANGED, sends: sent.sends(changed["would_send"]), step: changed["step"]) if changed

    output_of_answer(sent, sent: true, would_send: shown.except(Chat::BrowserCheck::SEND_DIGEST))
  rescue Chat::BrowserCheck::Refused => refused
    raise Refused, refused.message
  rescue AbilityGateway::PendingApproval => pending
    wait_for(pending.approval)
  rescue AbilityGateway::Denied
    raise Refused, Workflow::AgentRun.new(run: @run).refusal(check.sends? ? Ability::Action::BROWSER_SUBMIT : Ability::Action::BROWSER_READ)
  rescue Integrations::Error => error
    raise Failed, "The browser did not run: #{error.message}"
  end


  # The path read only, which stops before anything the page would send. For a send, on the screen size the send uses.
  def look_only(sending: false)
    given = check.to_params.except(KEY_SEND_STEP)
    given[KEY_VIEWPORTS] = check.viewports.first(1) if sending
    Chat::BrowserCheck.from(given, sends_allowed: false)
  end

  # keep is false for the look before a send, so the run keeps only the send's screenshots, as many as it reports.
  def browse(chosen, action_key, approval_id: nil, expected_send: nil, keep: true)
    blocked = workspace.browser_pages_blocked_reason(chosen.planned_pages)
    raise Refused, blocked if blocked

    agent_run = Workflow::AgentRun.new(run: @run, record: record, approval_id: approval_id)
    answer = nil
    agent_run.tool_call(action_key: action_key, params: chosen.to_params.merge("pages" => chosen.planned_pages)) do |authorization|
      answer = Chat::Browsing.run(workspace: workspace, box_key: @run.code_box_key, check: chosen, expected_send: expected_send)
      authorization.answer_failed!(answer.error) if answer.error
      answer.words
    end
    keep_screenshots(answer) if keep
    answer
  end

  def keep_screenshots(answer)
    return if record.nil? || answer.viewports.empty?

    chat = Chat.find_by(owner: record) ||
           Chat.open!(owner: record, workspace: workspace, model_choice: FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: workspace))
    @screenshots = Chat::Screenshot.record!(chat, answer.viewports, digest: check.digest).size
  end

  def output_of_answer(answer, sent:, would_send: nil)
    raise Failed, "The browser could not check #{check.url}: #{answer.error}" if answer.error

    first = answer.viewports.first.to_h
    {
      OUTPUT_OK => answer.ok?, OUTPUT_TROUBLE => answer.trouble, OUTPUT_STATUS => first["status"], OUTPUT_TITLE => first["title"],
      OUTPUT_FINAL_URL => first["final_url"], OUTPUT_TEXT => first["page_text"].to_s.truncate(TEXT_LIMIT), OUTPUT_TIMINGS => first["timings_ms"],
      OUTPUT_SCREENSHOTS => @screenshots.to_i, OUTPUT_SENT => sent, OUTPUT_WOULD_SEND => would_send
    }
  end
end

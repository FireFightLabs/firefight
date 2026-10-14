# Looks at an address from outside, as a user meets it, from the run's sandbox: whether it answers and with what status,
# where it redirects, its TLS certificate and how long it has left, its DNS records and how long each part took. It
# only reads, so it is a check that can follow a change.
class DefinedWorkflow::Steps::CheckFromOutside < DefinedWorkflow::Steps::Sandbox
  kind "check_from_outside"
  label "Check from outside"
  group GROUP_SANDBOX

  KEY_URL = "url".freeze
  KEY_METHOD = "method".freeze
  METHODS = %w[GET HEAD].freeze
  OUTPUT_OK = "ok".freeze
  OUTPUT_STATUS = "status".freeze
  OUTPUT_FINAL_URL = "final_url".freeze
  OUTPUT_DAYS_LEFT = "certificate_days_left".freeze
  OUTPUT_TRUSTED = "certificate_trusted".freeze
  OUTPUT_DNS = "dns".freeze
  OUTPUT_TIMINGS = "timings_ms".freeze
  OUTPUT_ERROR = "error".freeze
  OUTPUT_REGION = "region".freeze
  OUTPUTS = [ OUTPUT_OK, OUTPUT_STATUS, OUTPUT_FINAL_URL, OUTPUT_DAYS_LEFT, OUTPUT_TRUSTED, OUTPUT_DNS, OUTPUT_TIMINGS, OUTPUT_ERROR, OUTPUT_REGION ].freeze

  config_help "url (the address, such as https://shop.example.com), method (GET or HEAD, GET by default). Outputs ok (it answered below 400 " \
              "with a trusted certificate), status, final_url, certificate_days_left, certificate_trusted, dns, timings_ms, error and region."

  class << self
    def changes?(_config, _workspace) = false

    def checks?(_config, _workspace) = true

    def output_fields(_config) = OUTPUTS

    def problems(step, workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      found = sandbox_problems(config, named, workspace)
      found << "#{named} needs the address it checks." if config[KEY_URL].to_s.strip.empty?
      found << "#{named} checks with GET or HEAD." unless config[KEY_METHOD].blank? || METHODS.include?(config[KEY_METHOD].to_s.upcase)
      found
    end

    def describe(config, _workspace) = "#{config[KEY_METHOD].presence || 'GET'} #{config[KEY_URL]}".truncate(200)
  end

  def perform
    raise Refused, UNAVAILABLE unless Integrations::Terminal.available?(workspace)

    url = @config[KEY_URL].to_s.strip
    method = (@config[KEY_METHOD].presence || METHODS.first).to_s.upcase
    agent_run = Workflow::AgentRun.new(run: @run, record: record)
    checked = in_sandbox do
      agent_run.tool_call(action_key: Ability::Action::SANDBOX_COMMAND, params: { KEY_URL => url, KEY_METHOD => method }) do
        terminal.check(url, method: method)
      end.value
    end
    read(checked.answer, checked.region)
  rescue Integrations::Error => error
    raise Failed, "The check did not run: #{error.message}"
  rescue AbilityGateway::Denied
    raise Refused, agent_run.refusal(Ability::Action::SANDBOX_COMMAND)
  end

  private

  def read(answer, region)
    http = answer["http"].to_h
    tls = answer["tls"].to_h
    status = http["status"]
    trusted = http["certificate_trusted"]
    {
      OUTPUT_OK => status.present? && status.to_i < 400 && trusted != false, OUTPUT_STATUS => status, OUTPUT_FINAL_URL => http["final_url"],
      OUTPUT_DAYS_LEFT => tls["days_left"], OUTPUT_TRUSTED => trusted, OUTPUT_DNS => answer.dig("dns", "records"), OUTPUT_TIMINGS => http["timings_ms"],
      OUTPUT_ERROR => http["error"].presence || answer.dig("dns", "error").presence || tls["error"].presence, OUTPUT_REGION => region
    }
  end
end

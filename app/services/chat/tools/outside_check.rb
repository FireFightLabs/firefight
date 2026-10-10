# How an address looks from outside, as a user's browser would reach it: what DNS answers, the HTTP status and how long
# each part of the request took, and the certificate's expiry and whether it is trusted. It runs in Halon's sandbox, so
# it sees from the sandbox's one region, and says which. Uptime monitors a workspace connected check from several
# regions, and the answer names them for the rest. Only GET and HEAD, so a check never changes anything.
class Chat::Tools::OutsideCheck < RubyLLM::Tool
  NAME = "check_from_outside".freeze
  ACTION = Ability::Action::SANDBOX_COMMAND
  URL_ARG = "url".freeze
  METHOD_ARG = "method".freeze
  METHODS = %w[GET HEAD].freeze
  # Fewer days than this before a certificate expires is said as a warning.
  EXPIRY_WARNING_DAYS = 14

  description "Check an address from outside, as a user reaches it: DNS records, the HTTP status, redirects and timing " \
              "(DNS, connect, TLS, first byte, total), and the TLS certificate (issuer, expiry, days left, whether it is trusted " \
              "and covers the host). Runs from the sandbox and says which region that is. Use it to tell an outage from a " \
              "problem on one path, a slow phase, or a certificate or DNS fault."

  def self.all(agent_run) = Integrations::Terminal.available?(agent_run.workspace) ? [ new(agent_run) ] : []

  def self.tool_name = NAME

  def initialize(agent_run)
    super()
    @agent_run = agent_run
  end

  def name = NAME

  def parameters_schema
    { "type" => "object", "required" => [ URL_ARG ], "properties" => {
      URL_ARG => { "type" => "string", "description" => "The address, such as https://shop.example.com/health, or a hostname" },
      METHOD_ARG => { "type" => "string", "enum" => METHODS, "description" => "GET or HEAD (optional, GET)" }
    } }
  end

  def call(tool_call: nil, **arguments)
    given = arguments.transform_keys(&:to_s)
    url = given[URL_ARG].to_s.strip
    verb = given[METHOD_ARG].to_s.strip.upcase.presence || METHODS.first
    return refused(tool_call, "Only GET or HEAD checks run from outside, since a check never changes anything.") unless METHODS.include?(verb)
    return refused(tool_call, "Give the address to check.") if url.empty?

    said = @agent_run.tool_call(action_key: ACTION, params: { URL_ARG => url, METHOD_ARG => verb }, tool_name: NAME,
                                label: "Check #{url.truncate(80)} from outside") { checked(url, verb) }
    Chat::Tools.hand_over(@agent_run, NAME, said)
  rescue Integrations::Error => error
    refused(tool_call, FirefightAi::Evidence.frame(NAME, "The check did not run: #{error.message}"))
  end

  private

  def checked(url, verb)
    checked = Integrations::Terminal.new(key: @agent_run.code_box_key, workspace: @agent_run.workspace).check(url, method: verb)
    answer = checked.answer
    return "The check could not run: #{answer['error']}" if answer["error"].present? && answer["host"].blank?

    [ "#{verb} #{answer['url']}, checked #{from(checked.region)}.", dns_line(answer["dns"].to_h), http_line(answer["http"].to_h),
      tls_line(answer["tls"]), elsewhere ].compact.join("\n")
  end

  def from(region) = region ? "from the sandbox in #{region}" : "from the sandbox, in a region this install does not name"

  def dns_line(dns)
    return "DNS: #{dns['error']}" if Array(dns["records"]).empty?

    records = dns["records"].map { |record| "#{record['type']} #{record['value']} (TTL #{record['ttl']}s)" }
    "DNS (#{dns['ms']} ms): #{records.join(', ')}."
  end

  def http_line(http)
    timings = http["timings_ms"].to_h
    phases = %w[dns connect tls first_byte total].filter_map { |phase| "#{phase.tr('_', ' ')} #{timings[phase]} ms" if timings[phase] }
    return "HTTP: failed, #{http['error']}#{" (#{phases.join(', ')})" if phases.any?}." if http["status"].nil?

    redirected = http["redirects"].to_i.positive? ? " after #{http['redirects']} redirect#{'s' if http['redirects'].to_i > 1} to #{http['final_url']}" : ""
    reached = http["remote_ip"].present? ? " from #{http['remote_ip']}" : ""
    "HTTP: #{http['status']}#{redirected}#{reached}. #{phases.join(', ')}."
  end

  def tls_line(tls)
    return if tls.nil?
    return "Certificate: could not be read, #{tls['error']}." if tls["error"].present?

    days = tls["days_left"].to_i
    expiry = days.negative? ? "expired #{-days} days ago" : "expires in #{days} days"
    warning = days.between?(0, EXPIRY_WARNING_DAYS - 1) ? " Soon, renew it." : ""
    covers = tls["matches_host"] ? "covers the host" : "does not cover the host (it names #{Array(tls['names']).first(5).join(', ')})"
    "Certificate: #{tls['subject']}, issued by #{tls['issuer']}, #{expiry} (#{tls['not_after']}), #{covers}.#{warning}"
  end

  # One box sees from one place. A connected uptime monitor checks from several, and resource_status reads it.
  def elsewhere
    names = Integrations::Capabilities.outside_checkers(@agent_run.workspace).map(&:display_name)
    return "This is one place only. No uptime monitor that checks from several regions is connected." if names.empty?

    "This is one place only. #{names.to_sentence} #{names.one? ? 'checks' : 'check'} from several regions: resource_status with the hostname reads their checks region by region."
  end

  def refused(tool_call, text)
    Chat::Tools.mark_failed(@agent_run, tool_call&.id)
    text
  end
end

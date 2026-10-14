# What Halon's browser saw on a check, as sandbox/browser_check.mjs answers it, put into words for Halon and for a fix
# step's result. Everything in it came from an outside page, so whoever reads it treats it as evidence, never instructions.
class Chat::BrowserCheck::Answer
  STOP_SENDS_DATA = "sends_data".freeze
  STOP_CHANGED_REQUEST = "changed_request".freeze
  STOP_STEP_FAILED = "step_failed".freeze
  STOP_PAGE_CAP = "page_cap".freeze
  STOP_DEADLINE = "deadline".freeze
  # Each list is cut to this many lines for Halon. The person sees the page itself.
  LINES_SHOWN = 10
  HIDDEN = "[hidden]".freeze

  attr_reader :check, :region, :login_name

  # secrets are values that must never be read back, such as a test login's password, taken out of everything the page
  # said should a page echo one.
  def initialize(raw, check:, region: nil, login_name: nil, secrets: [])
    @raw = scrubbed(raw.to_h, Array(secrets).compact_blank)
    @check = check
    @region = region
    @login_name = login_name
  end

  def error = @raw["error"].presence

  def viewports = Array(@raw["viewports"])

  # The screen size that stopped before something it would send, when one did.
  def stopped_to_send = viewports.find { |viewport| [ STOP_SENDS_DATA, STOP_CHANGED_REQUEST ].include?(viewport.dig("stopped", "reason")) }

  # Where a send stopped because the page no longer sends what was confirmed, with what it sends now, or nil.
  def changed_request
    viewports.map { |viewport| viewport["stopped"].to_h }.find { |stopped| stopped["reason"] == STOP_CHANGED_REQUEST }
  end

  # A request a page would send, as one line: the method, the address and the fields shown.
  def sends(would)
    would = would.to_h
    fields = Array(would["fields"]).first(Chat::BrowserCheck::FIELDS_SHOWN).map { |field| "#{field['name']}=#{field['value']}" }
    "#{would['method']} #{would['url']}#{" with #{fields.join(', ')}" if fields.any?}"
  end

  # What went wrong on the page, a sentence each, empty when it loaded and every step passed. A fix's page check and a
  # watch go by it.
  def trouble
    return [ "The check did not run: #{error}" ] if error

    viewports.flat_map do |viewport|
      label = Chat::BrowserCheck.viewport_label(viewport["name"])
      status = viewport["status"].to_i
      errors = console(viewport).count { |line| line["type"] != "warning" }
      failed = Array(viewport["steps"]).reject { |step| step["ok"] }
      # A missing icon is not a broken page, so only requests that never answered or answered with a server error count.
      broken = Array(viewport["failed_requests"]).select { |request| request["status"].nil? || request["status"].to_i >= 500 }
      [
        ("#{label}: the page answered #{status}." if status >= 400),
        ("#{label}: the page did not load." if status.zero? && viewport["stopped"].blank?),
        ("#{label}: #{errors} console #{'error'.pluralize(errors)}." if errors.positive?),
        *failed.map { |step| "#{label}: step #{step['n']} failed, #{step['error']}" },
        ("#{label}: logging in failed, #{viewport.dig('login', 'error')}" if viewport["login"].is_a?(Hash) && viewport.dig("login", "ok") == false),
        ("#{label}: #{broken.size} #{'request'.pluralize(broken.size)} failed or answered with a server error." if broken.any?)
      ].compact
    end
  end

  def ok? = trouble.empty?

  # The whole check in words. can_send says whether this run could send a stopped step once the person agrees.
  def words(can_send: false)
    return "The browser could not check #{check.url}: #{error}" if error

    lines = [ "Checked #{check.url} in Halon's browser, #{from}." ]
    lines += viewports.map { |viewport| viewport_words(viewport) }
    lines << sending_words(can_send) if stopped_to_send
    lines << "A screenshot of each screen size is shown to the person in the chat. Say what you saw in words, they can see the page."
    lines.join("\n\n")
  end

  private

  def from = region ? "from the sandbox in #{region}" : "from the sandbox, in a region this install does not name"

  def viewport_words(viewport)
    label = Chat::BrowserCheck.viewport_label(viewport["name"])
    [
      "#{label} (#{viewport['width']}x#{viewport['height']}): #{headline(viewport)}",
      login_line(viewport), timings_line(viewport), steps_line(viewport), stopped_line(viewport),
      list("Console", console(viewport)) { |line| "#{line['type']}: #{line['text']}#{" (#{line['url']})" if line['url'].present?}" },
      list("Failed requests", viewport["failed_requests"]) { |request| "#{request['method']} #{request['url']}: #{request['status'] || request['error']}" },
      list("Sent by the page on its own while it loaded", viewport["load_sends"]) { |request| "#{request['method']} #{request['url']}" },
      list("Blocked by Firefight, since they would send data (not the site's fault)", viewport["blocked_requests"]) do |request|
        "#{request['method']} #{request['url']}#{" (#{request['reason']})" if request['reason'].present?}"
      end,
      ("Downloads refused: #{viewport['downloads_refused']}." if viewport["downloads_refused"].to_i.positive?),
      ("Visible error text: #{viewport['error_text']}" if viewport["error_text"].present?),
      ("Page text: #{viewport['page_text']}" if viewport["page_text"].present?),
      *Array(viewport["notes"]).map(&:to_s)
    ].compact.join("\n")
  end

  def headline(viewport)
    status = viewport["status"].presence || "no answer"
    title = viewport["title"].present? ? ", titled \"#{viewport['title']}\"" : ""
    pages = viewport["pages"].to_i
    "#{status} at #{viewport['final_url'].presence || check.url}#{title}, #{pages} #{'page'.pluralize(pages)} loaded."
  end

  def login_line(viewport)
    login = viewport["login"]
    return unless login.is_a?(Hash)
    return "Logged in with the saved test login#{" for #{login_name}" if login_name}." if login["ok"]

    "Logging in with the saved test login#{" for #{login_name}" if login_name} failed: #{login['error'].presence || 'the login form was still there after sending it'}."
  end

  def timings_line(viewport)
    timings = viewport["timings_ms"].to_h
    phases = %w[dns connect tls first_byte dom_content_loaded load].filter_map do |phase|
      "#{phase.tr('_', ' ').sub('dom content loaded', 'DOM ready')} #{timings[phase]} ms" if timings[phase]
    end
    "Timings of the last page: #{phases.join(', ')}." if phases.any?
  end

  def steps_line(viewport)
    steps = Array(viewport["steps"])
    return if steps.empty?

    shown = steps.map do |step|
      asked = check.steps[step["n"].to_i - 1]
      what = asked ? Chat::BrowserCheck.step_words(asked) : step["action"]
      "#{step['n']}. #{what}: #{step['ok'] ? 'done' : "failed, #{step['error']}"}"
    end
    "Steps: #{shown.join(' ')}"
  end

  def stopped_line(viewport)
    stopped = viewport["stopped"].to_h
    case stopped["reason"]
    when STOP_SENDS_DATA then "Stopped before step #{stopped['step']}, since it would send data: #{sends(stopped['would_send'])}. Nothing was sent."
    when STOP_CHANGED_REQUEST
      "Stopped at step #{stopped['step']}: the page now sends #{sends(stopped['would_send'])}, not what the person agreed to. Nothing was sent."
    when STOP_PAGE_CAP then "Stopped at step #{stopped['step']}: it reached #{Chat::BrowserCheck::PAGES_PER_VIEWPORT} pages, the most one check loads."
    when STOP_DEADLINE then "Stopped at step #{stopped['step']}: the check reached its time limit of #{Chat::BrowserCheck::DEADLINE_SECONDS} seconds."
    end
  end

  def sending_words(can_send)
    step = stopped_to_send.dig("stopped", "step")
    return "This run only reads, so nothing a page would send is sent from here." unless can_send

    "To send it, ask the person: call #{Chat::BrowserCheck::TOOL_NAME} again with the same url, steps and log_in, send_step #{step}, an " \
      "intent saying what it sends and why, and because. They are shown this page and what it sends, and nothing is sent until they confirm."
  end

  def console(viewport) = Array(viewport["console"])

  def list(title, items)
    items = Array(items)
    return if items.empty?

    shown = items.first(LINES_SHOWN).map { |item| "- #{yield(item)}" }
    shown << "- and #{items.size - LINES_SHOWN} more" if items.size > LINES_SHOWN
    "#{title}:\n#{shown.join("\n")}"
  end

  def scrubbed(value, secrets)
    return value if secrets.empty?

    case value
    when Hash then value.transform_values { |inner| scrubbed(inner, secrets) }
    when Array then value.map { |inner| scrubbed(inner, secrets) }
    when String then secrets.reduce(value) { |text, secret| text.gsub(secret, HIDDEN) }
    else value
    end
  end
end

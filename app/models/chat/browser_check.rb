# One look at a website in Halon's browser, as asked: the address, a short path of steps, the screen sizes and whether to
# log in first with the site's saved test login. send_step names the one step the person agreed may send what the page
# sends, such as a form. Checked here before anything runs, so the sandbox is only ever handed a path it can follow.
class Chat::BrowserCheck
  # The sentence says what was wrong with what was asked.
  class Refused < StandardError; end

  # The tool Halon checks a page with, named here so what a check says back can tell Halon how to send.
  TOOL_NAME = "check_in_browser".freeze

  VIEWPORTS = {
    "desktop" => { label: "Desktop", size: "1366x900" }.freeze,
    "phone" => { label: "Phone", size: "412x915" }.freeze
  }.freeze

  ACTION_GOTO = "goto".freeze
  ACTION_CLICK = "click".freeze
  ACTION_FILL = "fill".freeze
  ACTION_PRESS = "press".freeze
  ACTION_WAIT_FOR_TEXT = "wait_for_text".freeze
  ACTION_EXPECT_TEXT = "expect_text".freeze
  ACTIONS = [ ACTION_GOTO, ACTION_CLICK, ACTION_FILL, ACTION_PRESS, ACTION_WAIT_FOR_TEXT,
                    ACTION_EXPECT_TEXT ].freeze
  # Only a click or a key press can send what a page sends, so only those can be the step a person lets send.
  SENDING_ACTIONS = [ ACTION_CLICK, ACTION_PRESS ].freeze
  STEP_FIELDS = %w[action url text role name label placeholder value key].freeze

  MAX_STEPS = 12
  TEXT_LIMIT = 500
  KEY_FORMAT = /\A[A-Za-z0-9]+(\+[A-Za-z0-9]+)*\z/
  # Each screen size loads at most this many pages, so a path that loops ends.
  PAGES_PER_VIEWPORT = 10
  # The whole check, every screen size, ends after this, saying what it saw so far.
  DEADLINE_SECONDS = 120
  # The fields of what a page would send that the person is shown.
  FIELDS_SHOWN = 30
  SCHEMES = %w[http https].freeze
  # A scheme with no slashes, such as javascript: or data:. A host and port, such as shop.example.com:8080, is not one.
  OTHER_SCHEME = /\A(?!https?:)[a-z][a-z0-9+.\-]*:(?!\d)/i

  # Reads what Halon asked, refusing anything the browser could not follow. viewports defaults to both sizes, and a
  # check that may send runs on the first one only, so nothing is ever sent twice.
  def self.from(given, sends_allowed: true)
    given = given.to_h.stringify_keys
    url = address!(given["url"], "the address")
    steps = Array(given["steps"]).map.with_index(1) { |step, number| step!(step, number) }
    raise Refused, "A path has at most #{MAX_STEPS} steps. Check a shorter path, or split it into two checks." if steps.size > MAX_STEPS

    sizes = Array(given["viewports"]).map(&:to_s).uniq.presence || VIEWPORTS.keys
    unknown = sizes - VIEWPORTS.keys
    raise Refused, "#{unknown.join(' and ')} is not a screen size. Use #{VIEWPORTS.keys.join(' or ')}." if unknown.any?

    send_step = given["send_step"].presence&.to_i
    if send_step
      raise Refused, "This run only reads, so nothing a page would send is sent from here." unless sends_allowed
      raise Refused, "send_step #{send_step} is not one of the steps." unless send_step.between?(1, steps.size)
      unless SENDING_ACTIONS.include?(steps[send_step - 1]["action"])
        raise Refused, "Step #{send_step} is not a click or a key press, so it sends nothing."
      end

      sizes = sizes.first(1)
    end
    new(url: url, steps: steps, viewports: sizes, log_in: ActiveModel::Type::Boolean.new.cast(given["log_in"]) == true, send_step: send_step)
  end

  def self.address!(value, what)
    text = value.to_s.strip
    raise Refused, "Give #{what} to open." if text.empty?

    raise Refused, "Only http and https addresses open in the browser." if text.match?(OTHER_SCHEME)

    text = "https://#{text}" unless text.include?("://")
    parsed = URI.parse(text)
    raise Refused, "Only http and https addresses open in the browser." unless SCHEMES.include?(parsed.scheme)
    raise Refused, "#{what.capitalize} has no host." if parsed.host.blank?
    raise Refused, "Leave the user name and password out of #{what}. A saved test login logs the browser in." if parsed.userinfo.present?

    parsed.to_s
  rescue URI::InvalidURIError
    raise Refused, "#{text} is not an address."
  end

  def self.step!(step, number)
    raise Refused, "Step #{number} is not an object with an action." unless step.is_a?(Hash)

    given = step.stringify_keys.slice(*STEP_FIELDS).transform_values { |value| value.to_s.strip }.compact_blank
    action = given["action"]
    raise Refused, "Step #{number} has no action. Use one of #{ACTIONS.join(', ')}." unless ACTIONS.include?(action)

    too_long = given.find { |_field, value| value.length > TEXT_LIMIT }
    raise Refused, "Step #{number}'s #{too_long.first} is longer than #{TEXT_LIMIT} characters." if too_long

    missing = missing_in(action, given)
    raise Refused, "Step #{number} (#{action}) needs #{missing}." if missing

    given["url"] = address!(given["url"], "step #{number}'s address") if action == ACTION_GOTO
    given
  end

  # What a step cannot run without, in words, or nil.
  def self.missing_in(action, given)
    target = given["text"] || given["label"] || (given["role"] && given["name"])
    case action
    when ACTION_GOTO then "a url" unless given["url"]
    when ACTION_CLICK then "text, label, or role and name, to find what to click" unless target
    when ACTION_FILL
      return "a value to type" unless given.key?("value")

      "label, placeholder, or role and name, to find the field" unless given["label"] || given["placeholder"] || (given["role"] && given["name"])
    when ACTION_PRESS then "a key such as Enter or Control+K" unless given["key"].to_s.match?(KEY_FORMAT)
    else "the text to look for" unless given["text"]
    end
  end

  def self.viewport_label(name) = VIEWPORTS.fetch(name.to_s, {})[:label] || name.to_s.humanize

  attr_reader :url, :steps, :viewports, :log_in, :send_step

  def initialize(url:, steps:, viewports:, log_in:, send_step:)
    @url = url
    @steps = steps
    @viewports = viewports
    @log_in = log_in
    @send_step = send_step
  end

  def sends? = send_step.present?

  def host = URI.parse(url).host.to_s.downcase

  # The same address, steps and login, whatever the screen sizes. A send is only ever confirmed against the check the
  # person was shown, so this ties the two together.
  def digest = Digest::SHA256.hexdigest([ url, steps, log_in ].to_json)

  # The most pages this check may load, counted against the workspace's hour before it runs.
  def planned_pages
    loads = 1 + steps.count { |step| [ ACTION_GOTO, *SENDING_ACTIONS ].include?(step["action"]) } + (log_in ? 2 : 0)
    viewports.size * [ loads, PAGES_PER_VIEWPORT ].min
  end

  # The ledger keeps everything asked, so a call a rule held runs exactly as asked once approved.
  def to_params = { "url" => url, "steps" => steps, "viewports" => viewports, "log_in" => log_in, "send_step" => send_step }.compact

  # What the sandbox's browser is handed, without the login, which only the run adds.
  def to_spec(expected_send: nil)
    { "url" => url, "viewports" => viewports, "steps" => steps, "send_step" => send_step, "expected_send" => expected_send,
      "max_pages" => PAGES_PER_VIEWPORT, "deadline_seconds" => DEADLINE_SECONDS }
  end

  # One line for a step, as the person and Halon read it.
  def self.step_words(step)
    target = step["text"] || step["label"] || step["placeholder"] || [ step["role"], step["name"] ].compact.join(" ")
    case step["action"]
    when ACTION_GOTO then "go to #{step['url']}"
    when ACTION_CLICK then "click \"#{target}\""
    when ACTION_FILL then "type into \"#{target}\""
    when ACTION_PRESS then "press #{step['key']}#{" in \"#{target}\"" if target.present?}"
    when ACTION_WAIT_FOR_TEXT then "wait for \"#{step['text']}\""
    else "expect \"#{step['text']}\""
    end
  end
end

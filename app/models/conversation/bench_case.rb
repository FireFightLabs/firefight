# What a bench replay plays back: who is asking and where, what the person says turn by turn and how they answer a
# confirmation, the tools Halon is offered, what each call answers, and what a good run reaches. A scenario is one of
# these written by hand from a real failure, with no customer data, in config/halon_bench. A real chat becomes one
# from its own record (Conversation::Rehearsal.capture).
class Conversation::BenchCase
  DIRECTORY = Rails.root.join("config/halon_bench")
  # Tools many scenarios offer, described once. A scenario names one of these, or describes its own.
  SHARED_TOOLS = DIRECTORY.join("_tools.yml")

  # What a call no answer was recorded for gets, so the replay goes on and the count says where it left the record.
  NOT_RECORDED = "This call was not made in the chat being replayed, so it has no recorded result.".freeze

  DECISION_APPROVE = "approve"
  DECISION_DENY = "deny"
  DECISIONS = [ DECISION_APPROVE, DECISION_DENY ].freeze

  # How much of a tool's description a default answer listing the tools gives, as a catalog line does.
  TOOL_LINE = 200

  # What a scenario's replay is expected to spend when it says nothing of its own, in cents. A scenario's reference
  # is what the cheapest model that finished it spent on the first real run, so the cost score tells models apart.
  DEFAULT_REFERENCE_CENTS = 2.0

  class Invalid < StandardError; end

  # source is firefight for Firefight's own tools, or a provider's key for a connected tool. A connected tool that reads
  # owes the answer a check before it goes out, as in a live chat. reads says every call only reads, and reads_when
  # names argument values that make a call a read, such as a GET through a general API tool. confirms says a call that
  # changes something waits for the person. A read never waits. default is what a call answers when the scenario
  # recorded nothing that matches, where %{tools} lists the tools the scenario offers.
  # base says the tool is in hand from the start of a chat, as a chat's own tools are live. The rest sit in a group
  # that open_tools makes callable, named by group or, without one, by whose the tool is.
  Tool = Data.define(:name, :description, :parameters, :source, :reads, :reads_when, :confirms, :default, :base, :group) do
    def outside? = source != Chat::Skill::SOURCE_FIREFIGHT

    def group_key = group.presence || source

    def reads?(arguments)
      reads || (reads_when.any? && reads_when.all? { |key, values| Array(values).map { |value| value.to_s.downcase }.include?(arguments[key].to_s.downcase) })
    end

    def asks?(arguments) = confirms && !reads?(arguments)
  end

  # match is the arguments a call must carry for this answer, a subset compared without regard to case, where a value
  # written /like this/ is a pattern. No match answers any call to the tool. times is how often it answers before the
  # next one takes over, nil for always, so a run's status can move from running to failed between two reads. reads
  # marks a call that only read through a tool that cannot tell, such as a script, so asking the person to confirm it
  # was not needed. after names a call (a tool and what it must match) that has to have run first, so a read can show
  # the state a change left, such as a token refused once it was rotated.
  Answer = Data.define(:tool, :match, :result, :failed, :times, :reads, :after) do
    def matches?(name, arguments)
      tool == name && match.all? { |key, wanted| Conversation::BenchCase.same?(wanted, arguments[key]) }
    end

    # ran is each call made so far in the replay, as a tool name and its arguments.
    def ready?(ran)
      after.nil? || ran.any? { |name, arguments| name == after["tool"] && after["match"].to_h.all? { |key, wanted| Conversation::BenchCase.same?(wanted, arguments[key]) } }
    end
  end

  # decisions answer the confirmations the turn asks for, in order. A confirmation with none left is left waiting, and
  # the next turn moves past it as a person would by saying something else.
  Turn = Data.define(:said, :decisions)

  # outcome and next_step are what the judge reads a good run against. evidence is texts a right answer cites, calls
  # and never_calls are tools that taking the next step does and does not call. reference_cents is what the replay is
  # held to spend.
  Expect = Data.define(:outcome, :next_step, :evidence, :calls, :never_calls, :reference_cents) do
    def self.none = new(outcome: nil, next_step: nil, evidence: [], calls: [], never_calls: [], reference_cents: DEFAULT_REFERENCE_CENTS)
  end

  attr_reader :key, :title, :shape, :source, :context, :turns, :tools, :answers, :expect

  def initialize(key:, title:, shape:, context:, turns:, tools:, answers:, expect:, source: nil)
    @key = key
    @title = title
    @shape = shape
    @source = source
    @context = context
    @turns = turns
    @tools = tools
    @answers = answers
    @expect = expect
  end

  def self.scenarios
    shared = shared_tools
    Dir[DIRECTORY.join("[!_]*.yml")].sort.map { |path| from_file(path, shared: shared) }
  end

  def self.shared_tools
    YAML.safe_load_file(SHARED_TOOLS).to_h { |name, data| [ name, data.merge("name" => name) ] }
  end

  def self.scenario(key) = scenarios.find { |scenario| scenario.key == key } || raise(Invalid, "No scenario is called #{key}.")

  def self.from_file(path, shared: shared_tools)
    from_hash(YAML.safe_load_file(path), key: File.basename(path, ".yml"), shared: shared)
  rescue Invalid => error
    raise Invalid, "#{File.basename(path)}: #{error.message}"
  end

  def self.from_hash(data, key:, shared: {})
    data = data.to_h.deep_stringify_keys
    tools = Array(data["tools"]).map { |tool| tool_from(tool.is_a?(String) ? shared.fetch(tool) { raise Invalid, "No shared tool is called #{tool}." } : tool) }
    case_for = new(
      key: key, title: required(data, "title"), shape: data["shape"].to_s, source: data["source"], context: data["context"].to_s.strip,
      turns: Array(data["turns"]).map { |turn| turn_from(turn) }, tools: tools,
      answers: Array(data["answers"]).map { |answer| answer_from(answer) }, expect: expect_from(data["expect"] || {})
    )
    case_for.tap(&:check!)
  end

  def self.tool_from(data)
    Tool.new(
      name: required(data, "name"), description: required(data, "description"), parameters: data["parameters"] || { "type" => "object", "properties" => {} },
      source: data["source"].presence || Chat::Skill::SOURCE_FIREFIGHT, reads: data["reads"] == true,
      reads_when: data["reads_when"].to_h, confirms: data["confirms"] == true, default: data["default"], base: data["base"] == true,
      group: data["group"]
    )
  end

  def self.answer_from(data)
    Answer.new(tool: required(data, "tool"), match: data["match"].to_h, result: data["result"].to_s, failed: data["failed"] == true,
               times: data["times"], reads: data["reads"] == true, after: data["after"])
  end

  def self.turn_from(data)
    data = { "said" => data } if data.is_a?(String)
    decisions = Array(data["decisions"]).map(&:to_s)
    raise Invalid, "A decision is approve or deny, not #{(decisions - DECISIONS).first}." if (decisions - DECISIONS).any?

    Turn.new(said: required(data, "said"), decisions: decisions)
  end

  def self.expect_from(data)
    Expect.new(
      outcome: data["outcome"], next_step: data["next_step"], evidence: Array(data["evidence"]).map(&:to_s),
      calls: Array(data["calls"]).map(&:to_s), never_calls: Array(data["never_calls"]).map(&:to_s),
      reference_cents: (data["reference_cents"] || DEFAULT_REFERENCE_CENTS).to_f
    )
  end

  def self.required(data, field)
    data[field].presence || raise(Invalid, "#{field} is missing.")
  end

  # A pattern written /like this/, or the same text whatever its case. A hash is compared key by key.
  def self.same?(wanted, given)
    return wanted.all? { |key, value| same?(value, given.to_h.stringify_keys[key.to_s]) } if wanted.is_a?(Hash)
    return given.to_s.match?(Regexp.new(wanted[1..-2], Regexp::IGNORECASE)) if wanted.is_a?(String) && wanted.length > 2 && wanted.start_with?("/") && wanted.end_with?("/")

    wanted.to_s.casecmp?(given.to_s)
  end

  def tool(name) = tools.find { |tool| tool.name == name }

  # Every name an answer or an expectation gives is a tool the case offers, so a typo fails loudly rather than leaving
  # a call that can never be answered.
  def check!
    raise Invalid, "turns is empty." if turns.empty?
    raise Invalid, "tools is empty." if tools.empty?

    names = tools.map(&:name)
    raise Invalid, "#{names.tally.find { |_name, count| count > 1 }.first} is offered twice." if names.uniq.size < names.size

    unknown = (answers.map(&:tool) + answers.filter_map { |answer| answer.after&.fetch("tool", nil) } + expect.calls + expect.never_calls).uniq - names
    raise Invalid, "#{unknown.to_sentence} #{unknown.one? ? 'is' : 'are'} not offered." if unknown.any?
  end

  # Answers a call from the record, the first one that matches, has not been used up and whose earlier call has run, or
  # the tool's default. used counts how often each answer was, by its place, and ran is the calls made so far.
  def answer_for(name, arguments, used, ran = [])
    found = answers.each_with_index.find do |answer, index|
      answer.matches?(name, arguments) && (answer.times.nil? || used[index] < answer.times) && answer.ready?(ran)
    end
    return found if found

    default = tool(name)&.default
    [ Answer.new(tool: name, match: {}, result: default.gsub("%{tools}", tool_list), failed: false, times: nil, reads: false, after: nil), nil ] if default
  end

  def tool_list = tools.map { |tool| "- #{tool.name}: #{tool.description.to_s.squish.truncate(TOOL_LINE)}" }.join("\n")

  # Written back as a scenario file, for a real chat someone wants to keep on the bench once its customer data is gone.
  def to_h
    {
      "title" => title, "shape" => shape.presence, "source" => source, "context" => context,
      "turns" => turns.map { |turn| { "said" => turn.said, "decisions" => turn.decisions.presence }.compact },
      "tools" => tools.map do |tool|
        { "name" => tool.name, "description" => tool.description, "parameters" => tool.parameters, "source" => tool.source,
          "reads" => tool.reads || nil, "reads_when" => tool.reads_when.presence, "confirms" => tool.confirms || nil, "default" => tool.default,
          "base" => tool.base || nil, "group" => tool.group }.compact
      end,
      "answers" => answers.map do |answer|
        { "tool" => answer.tool, "match" => answer.match.presence, "result" => answer.result, "failed" => answer.failed || nil,
          "times" => answer.times, "reads" => answer.reads || nil, "after" => answer.after }.compact
      end,
      "expect" => { "outcome" => expect.outcome, "next_step" => expect.next_step, "evidence" => expect.evidence.presence,
                    "calls" => expect.calls.presence, "reference_cents" => expect.reference_cents }.compact
    }.compact
  end
end

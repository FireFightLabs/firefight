# What a bench replay plays back: who is asking and where, what the person says turn by turn and how they answer a
# confirmation or a question in plain words, the tools Halon is offered, the world those tools read, what each call
# answers, and what a good run reaches. A scenario is one of these written by hand from a real failure, with no customer
# data, in config/halon_bench. A real chat becomes one from its own record (Conversation::Rehearsal.capture).
class Conversation::BenchCase
  DIRECTORY = Rails.root.join("config/halon_bench")
  # Tools many scenarios offer, described once. A scenario names one of these, or describes its own.
  SHARED_TOOLS = DIRECTORY.join("_tools.yml")

  # What a call no answer was recorded for gets in a real chat replayed, so the replay goes on and the count says where
  # it left the record.
  NOT_RECORDED = "This call was not made in the chat being replayed, so it has no recorded result.".freeze
  # What a call a scenario never scripted gets, as the provider would answer a request that finds nothing. Never a list
  # that fits any request, and never a change's "Done." for a read.
  NOTHING_FOUND = "Nothing matched that. The request found no record.".freeze
  NOTHING_CHANGED = "Nothing was changed. The request named nothing the provider holds.".freeze

  DECISION_APPROVE = "approve"
  DECISION_DENY = "deny"
  DECISIONS = [ DECISION_APPROVE, DECISION_DENY ].freeze

  # How much of a tool's description a default answer listing the tools gives, as a catalog line does.
  TOOL_LINE = 200

  # What a scenario's replay is expected to spend when it says nothing of its own, in cents. A scenario's reference
  # is what the cheapest model that finished it spent on the first real run, so the cost score tells models apart.
  DEFAULT_REFERENCE_CENTS = 2.0

  class Invalid < StandardError; end

  # source is firefight for Firefight's own tools, or a provider's key for a connected tool. reads says every call only reads, and reads_when
  # names argument values that make a call a read, such as a GET through a general API tool. confirms says a call that
  # changes something waits for the person. A read never waits. default is what a call answers when the scenario
  # recorded nothing that matches, where %{tools} lists the tools the scenario offers. reads_like names a tool whose
  # answer a call reads when nothing matches, such as what_changed reading the deploys recent_deploys lists, so two
  # tools reading the same world agree. request names the argument a general tool takes its request in, such as a
  # path or a script, which every answer to it must match, so no answer fits any request.
  # base says the tool is in hand from the start of a chat, as a chat's own tools are live. The rest sit in a group
  # that open_tools makes callable, named by group or, without one, by whose the tool is.
  Tool = Data.define(:name, :description, :parameters, :source, :reads, :reads_when, :confirms, :default, :base, :group, :reads_like, :request) do
    def outside? = source != Chat::Skill::SOURCE_FIREFIGHT

    def group_key = group.presence || source

    def reads?(arguments)
      reads || (reads_when.any? && reads_when.all? { |key, values| Array(values).any? { |value| Conversation::BenchCase.same?(value, arguments[key]) } })
    end

    def asks?(arguments) = confirms && !reads?(arguments)
  end

  # match is the arguments a call must carry for this answer, a subset compared without regard to case, where a value
  # written /like this/ is a pattern. No match answers any call to the tool. state names facts of the scenario's world
  # the answer holds for, and sets is what giving it makes true, so a run read as running by one tool reads as failed
  # through every tool once one read moved it on, and a read after a change shows what the change left. times is how
  # often it answers before the next one takes over, nil for always. reads marks a call that only read through a tool
  # that cannot tell, such as a script, so asking the person to confirm it was not needed.
  Answer = Data.define(:tool, :match, :result, :failed, :times, :reads, :state, :sets) do
    def initialize(tool:, match:, result:, failed: false, times: nil, reads: false, state: {}, sets: {}) = super

    def matches?(name, arguments)
      tool == name && match.all? { |key, wanted| Conversation::BenchCase.same?(wanted, arguments[key]) }
    end
  end

  # What the person answers to a question Halon asks in plain words rather than on a card. asked is a pattern its
  # question matches and say is the reply.
  Reply = Data.define(:asked, :say)

  # decisions answer the confirmations the turn asks for, in order. A confirmation with none left is left waiting, and
  # the next turn moves past it as a person would by saying something else. approves, refuses and answers say how the
  # person answers a plain words question during this turn, before what the whole chat says. sets moves the world on
  # when the person says it, as time passing does, such as an error rate that climbed by their second message.
  Turn = Data.define(:said, :decisions, :approves, :refuses, :answers, :sets) do
    def initialize(said:, decisions: [], approves: [], refuses: [], answers: [], sets: {}) = super
  end

  # outcome and next_step are what the judge reads a good run against. evidence is texts a right answer cites, calls
  # and never_calls are tools that taking the next step does and does not call. reference_cents is what the replay is
  # held to spend.
  Expect = Data.define(:outcome, :next_step, :evidence, :calls, :never_calls, :reference_cents) do
    def self.none = new(outcome: nil, next_step: nil, evidence: [], calls: [], never_calls: [], reference_cents: DEFAULT_REFERENCE_CENTS)
  end

  attr_reader :key, :title, :shape, :source, :context, :turns, :tools, :answers, :expect, :world, :person

  # captured is a real chat replayed from its record, where a call the chat never made says so.
  def initialize(key:, title:, shape:, context:, turns:, tools:, answers:, expect:, source: nil, world: {}, person: Person.none, captured: false)
    @key = key
    @title = title
    @shape = shape
    @source = source
    @context = context
    @turns = turns
    @tools = tools
    @answers = answers
    @expect = expect
    @world = world
    @person = person
    @captured = captured
  end

  def captured? = @captured

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
      answers: Array(data["answers"]).map { |answer| answer_from(answer) }, expect: expect_from(data["expect"] || {}),
      world: facts(data["world"]), person: person_from(data["person"] || {})
    )
    case_for.tap(&:check!)
  end

  def self.tool_from(data)
    Tool.new(
      name: required(data, "name"), description: required(data, "description"), parameters: data["parameters"] || { "type" => "object", "properties" => {} },
      source: data["source"].presence || Chat::Skill::SOURCE_FIREFIGHT, reads: data["reads"] == true,
      reads_when: data["reads_when"].to_h, confirms: data["confirms"] == true, default: data["default"], base: data["base"] == true,
      group: data["group"], reads_like: data["reads_like"], request: data["request"]
    )
  end

  def self.answer_from(data)
    Answer.new(tool: required(data, "tool"), match: data["match"].to_h, result: data["result"].to_s, failed: data["failed"] == true,
               times: data["times"], reads: data["reads"] == true, state: facts(data["state"]), sets: facts(data["sets"]))
  end

  def self.turn_from(data)
    data = { "said" => data } if data.is_a?(String)
    decisions = Array(data["decisions"]).map(&:to_s)
    raise Invalid, "A decision is approve or deny, not #{(decisions - DECISIONS).first}." if (decisions - DECISIONS).any?

    Turn.new(said: required(data, "said"), decisions: decisions, approves: patterns(data["approves"]), refuses: patterns(data["refuses"]),
             answers: replies(data["answers"]), sets: facts(data["sets"]))
  end

  def self.person_from(data)
    Person.new(approves: patterns(data["approves"]), refuses: patterns(data["refuses"]), answers: replies(data["answers"]), otherwise: data["otherwise"].presence)
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

  # The world's facts as text both ways, so a fact written yes or true in one place matches the other.
  def self.facts(data) = data.to_h.to_h { |name, value| [ name.to_s, value.to_s ] }

  def self.patterns(data) = Array(data).map(&:to_s)

  def self.replies(data)
    Array(data).map { |reply| Reply.new(asked: required(reply.to_h, "asked").to_s, say: required(reply.to_h, "say").to_s) }
  end

  # A pattern written /like this/, or the same text whatever its case. A hash is compared key by key.
  def self.same?(wanted, given)
    return wanted.all? { |key, value| same?(value, given.to_h.stringify_keys[key.to_s]) } if wanted.is_a?(Hash)
    return given.to_s.match?(pattern(wanted)) if pattern?(wanted)

    wanted.to_s.casecmp?(given.to_s)
  end

  def self.pattern?(wanted) = wanted.is_a?(String) && wanted.length > 2 && wanted.start_with?("/") && wanted.end_with?("/")

  def self.pattern(wanted) = Regexp.new(wanted[1..-2], Regexp::IGNORECASE)

  # Whether some text matches any of the patterns, each written /like this/ or as words it contains.
  def self.mentions?(patterns, text)
    patterns.any? { |wanted| pattern?(wanted) ? text.to_s.match?(pattern(wanted)) : text.to_s.downcase.include?(wanted.downcase) }
  end

  def tool(name) = tools.find { |tool| tool.name == name }

  # The same case offering more tools, such as those a live chat holds whatever the scenario lists.
  def offering(more)
    return self if more.empty?

    self.class.new(key: key, title: title, shape: shape, source: source, context: context, turns: turns, tools: tools + more,
                   answers: answers, expect: expect, world: world, person: person, captured: captured?)
  end

  # Every name an answer or an expectation gives is a tool the case offers, so a typo fails loudly rather than leaving
  # a call that can never be answered. A general tool's answers each say which requests they answer.
  def check!
    raise Invalid, "turns is empty." if turns.empty?
    raise Invalid, "tools is empty." if tools.empty?

    names = tools.map(&:name)
    raise Invalid, "#{names.tally.find { |_name, count| count > 1 }.first} is offered twice." if names.uniq.size < names.size

    unknown = (answers.map(&:tool) + expect.calls + expect.never_calls).uniq - names
    raise Invalid, "#{unknown.to_sentence} #{unknown.one? ? 'is' : 'are'} not offered." if unknown.any?

    loose = answers.find { |answer| (field = tool(answer.tool).request) && !answer.match.key?(field) }
    raise Invalid, "An answer to #{loose.tool} must match its #{tool(loose.tool).request}, so it never answers a request it was not written for." if loose
  end

  # Answers a call from the record with the first answer that matches, has not been used up and holds in the world as
  # it stands. Else what the tool reads like, or its default. world is the replay's Conversation::BenchCase::World, which
  # nothing here changes.
  def answer_for(name, arguments, world)
    found = answers.each_with_index.find do |answer, index|
      answer.matches?(name, arguments) && (answer.times.nil? || world.used[index] < answer.times) && world.holds?(answer.state)
    end
    return found if found

    offered = tool(name)
    like = offered&.reads_like && answer_for(offered.reads_like, arguments, world)&.first
    return [ Answer.new(tool: name, match: {}, result: like.result), nil ] if like

    [ Answer.new(tool: name, match: {}, result: offered.default.gsub("%{tools}", tool_list)), nil ] if offered&.default
  end

  # What a call nothing answers gets. In a real chat replayed it says the chat never made it, and in a scenario it is
  # what the provider says to a request that finds nothing.
  def unscripted(name, arguments)
    return NOT_RECORDED if captured?

    tool(name)&.asks?(arguments) ? NOTHING_CHANGED : NOTHING_FOUND
  end

  def tool_list = tools.map { |tool| "- #{tool.name}: #{tool.description.to_s.squish.truncate(TOOL_LINE)}" }.join("\n")

  # Written back as a scenario file, for a real chat someone wants to keep on the bench once its customer data is gone.
  def to_h
    {
      "title" => title, "shape" => shape.presence, "source" => source, "context" => context,
      "world" => world.presence,
      "person" => { "approves" => person.approves.presence, "refuses" => person.refuses.presence, "answers" => replies_h(person.answers),
                    "otherwise" => person.otherwise }.compact.presence,
      "turns" => turns.map do |turn|
        { "said" => turn.said, "decisions" => turn.decisions.presence, "approves" => turn.approves.presence, "refuses" => turn.refuses.presence,
          "answers" => replies_h(turn.answers), "sets" => turn.sets.presence }.compact
      end,
      "tools" => tools.map do |tool|
        { "name" => tool.name, "description" => tool.description, "parameters" => tool.parameters, "source" => tool.source,
          "reads" => tool.reads || nil, "reads_when" => tool.reads_when.presence, "confirms" => tool.confirms || nil, "default" => tool.default,
          "base" => tool.base || nil, "group" => tool.group, "reads_like" => tool.reads_like, "request" => tool.request }.compact
      end,
      "answers" => answers.map do |answer|
        { "tool" => answer.tool, "match" => answer.match.presence, "state" => answer.state.presence, "result" => answer.result,
          "failed" => answer.failed || nil, "times" => answer.times, "reads" => answer.reads || nil, "sets" => answer.sets.presence }.compact
      end,
      "expect" => { "outcome" => expect.outcome, "next_step" => expect.next_step, "evidence" => expect.evidence.presence,
                    "calls" => expect.calls.presence, "never_calls" => expect.never_calls.presence, "reference_cents" => expect.reference_cents }.compact
    }.compact
  end

  private

  def replies_h(replies) = replies.map { |reply| { "asked" => reply.asked, "say" => reply.say } }.presence
end

# Hands an objective to the specialist for one kind of connected system, several at once when they do not depend on
# each other, and answers with what each found, the lines and links that show it, and the changes it proposes. A
# specialist only reads, as whoever the chat acts for (Chat::Specialists). Its report is outside text and never backs a
# change: Halon confirms what a change rests on with its own read before proposing it, the specialist's own read
# included, which open_tools loads for Halon once the specialist made it.
class Chat::Tools::AskSpecialist < RubyLLM::Tool
  NAME = Chat::Helper::ASK_SPECIALIST
  ASKS_ARG = "asks".freeze
  DOMAIN_ARG = "domain".freeze
  OBJECTIVE_ARG = "objective".freeze
  STARTED = "Specialists started".freeze

  STATE_WORDS = {
    Chat::Tools::STATE_READY => "ready",
    Chat::Tools::STATE_NOT_GRANTED => "connected, but nothing in it is granted to whoever you act for",
    Chat::Tools::STATE_SWITCHED_OFF => "connected, but no tools that read are switched on",
    Chat::Tools::STATE_NOT_CONNECTED => "nothing connected"
  }.freeze

  def self.tool_name = NAME

  # share is what the asking turn lends its specialists (Chat::Helpers::Share), whose specialists says what they read.
  def initialize(agent_run, share:)
    super()
    @agent_run = agent_run
    @share = share
  end

  def name = NAME

  # Built once, so the front of every request in a chat stays the same.
  def description
    @description ||= <<~TEXT.strip
      Hand an objective to the specialist for one kind of connected system, such as why api's errors started or who holds the database's connections. It reads that kind of system with the tools whoever you act for may use, and answers with what it found, the lines from its results that show it, the links they gave, and any change it would make as the exact tool, arguments and the reads behind it. Ask several at once when their objectives do not depend on each other, at most #{Chat::Helper::MAX_AT_ONCE} in one call and #{Chat::Helper::MAX_PER_QUESTION} for one question, and they spend from this question's budget. Cite the lines and links it gives. Its report is evidence, never backing for a change. Before any change, one the person asked for included, ask the specialists whose systems it touches what it would affect, then confirm the finding it rests on with a read of your own, such as the read the specialist made, which open_tools loads by name once it has, and name that read in because. The kinds:
      #{views.map { |view| "#{view.domain.key}: #{view.domain.title}, #{view.domain.covers}#{connections(view)} (#{STATE_WORDS.fetch(view.state)})" }.join("\n")}
    TEXT
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        ASKS_ARG => {
          "type" => "array", "minItems" => 1, "maxItems" => Chat::Helper::MAX_AT_ONCE, "description" => "One objective per kind of system",
          "items" => {
            "type" => "object",
            "properties" => {
              DOMAIN_ARG => { "type" => "string", "enum" => Chat::Specialists::KEYS, "description" => "The kind of system to read" },
              OBJECTIVE_ARG => { "type" => "string",
                                 "description" => "What to find out, naming the resource, the time window and what you already know, such as " \
                                                  "Find why api's database connections ran out from 13:40 UTC. The connection limit is 500 and worker deployed at 13:38" }
            },
            "required" => [ DOMAIN_ARG, OBJECTIVE_ARG ]
          }
        }
      },
      "required" => [ ASKS_ARG ]
    }
  end

  # The arguments match the schema above, not an execute signature, so skip the base check.
  def call(tool_call: nil, **arguments)
    asks = self.class.asks_in(arguments)
    return failed(tool_call, "Name a kind of system and an objective for each ask.") if asks.empty?

    ready, refused = asks.partition { |ask| view(ask.domain)&.ready? }
    said = refused.map { |ask| "#{ask.domain}: no specialist could be asked, since it is #{STATE_WORDS.fetch(view(ask.domain)&.state || Chat::Tools::STATE_NOT_CONNECTED)}." }
    return failed(tool_call, said.join("\n")) if ready.empty?

    started = Time.current
    progress(STARTED, value: 0, total: ready.size)
    result = Chat::Helpers.run!(@agent_run, share: @share, tool_call_id: tool_call&.id.to_s, checks: ready.map { |ask| check(ask) }, on_done: method(:reported))
    Chat::Tools.mark_failed(@agent_run, tool_call&.id) if result.failed
    text = [ result.text, *proposed(tool_call), *said ].join("\n\n")
    said = Chat::Tools.hand_over(@agent_run, NAME, Chat::ToolCall::Outcome.new(value: text))
    [ said, Chat::Tools.charts_drawn(@agent_run, tool_call&.id.to_s, since: started) ].compact.join("\n\n")
  end

  Ask = Data.define(:domain, :objective)

  # The asks as the model sent them, leaving out any without an objective or a kind there is.
  def self.asks_in(arguments)
    Array(arguments.stringify_keys[ASKS_ARG]).filter_map do |given|
      given = given.to_h.stringify_keys
      objective = given[OBJECTIVE_ARG].to_s.strip
      domain = given[DOMAIN_ARG].to_s.strip
      Ask.new(domain: domain, objective: objective) if objective.present? && Chat::Specialists::KEYS.include?(domain)
    end
  end

  # What a person reads on the step, each kind with its objective folded under it, drawn like helpers while they work.
  def self.shown(arguments)
    asks = asks_in(arguments)
    titles = asks.map { |ask| Chat::Specialists.domain(ask.domain).title }
    Chat::Tools::Step.new(
      title: asks.size == 1 ? "Asked a specialist" : "Asked #{asks.size} specialists", headline: titles.join(", "),
      asked: asks.map { |ask| [ Chat::Specialists.domain(ask.domain).title, ask.objective ] }, card: Chat::Tools::Card.new(kind: Chat::Tools::CARD_HELPERS, category: nil)
    )
  end

  private

  def views = @views ||= @share.specialists.views

  def view(key) = views.find { |each| each.domain.key == key }

  def connections(view) = view.connections.any? ? ", through #{view.connections.to_sentence}" : ""

  def check(ask)
    title = "#{Chat::Specialists.domain(ask.domain).title}: #{ask.objective}"
    Chat::Helpers::Check.new(title: title, brief: ask.objective, deep: FirefightAi.configuration.specialists_on_main?, domain: ask.domain)
  end

  # Each tool the specialists of this call proposed a change through, with what it takes for Halon to make one.
  def proposed(tool_call)
    changes = Chat::Helper.where(chat_id: @agent_run.chat&.id, tool_call_id: tool_call&.id.to_s).in_order.flat_map(&:proposed_changes)
    changes.map { |change| change["tool"].to_s }.compact_blank.uniq.map { |name| @share.specialists.describe(name) }
  end

  def reported(done, total) = progress(format(Chat::Tools::Helpers::DONE, done: done, total: total), value: done, total: total)

  def failed(tool_call, text)
    Chat::Tools.mark_failed(@agent_run, tool_call&.id)
    text
  end
end

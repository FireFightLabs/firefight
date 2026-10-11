# Halon's theory board while it troubleshoots in a chat: two or three candidate causes, each open, confirmed or ruled
# out with the evidence that settled it, rewritten whole each call (Chat::Theory.replace!). A turn that names a cause
# while a strong alternative is still open is sent back once (Conversation::Checks), and a cause it confirms is looked
# at again by the challenger. A plain question needs no board.
class Chat::Tools::Theories < RubyLLM::Tool
  NAME = Chat::Theory::TOOL
  THEORIES_ARG = "theories".freeze

  description "Keep your theory board while you troubleshoot something broken, slow or wrong, never for a plain question. " \
              "List two or three candidate causes, each open, confirmed or ruled_out, with the evidence that settled it: the " \
              "read and what it showed. Mark the one you lead with. Test the open ones at once with run_helpers, or " \
              "ask_specialist when you hold it, rather than one after another. Name a cause only when it is confirmed and no " \
              "strong alternative is still open, or say plainly in your answer what is still open and what would settle it. " \
              "Each call replaces the whole board."

  def self.tool_name = NAME

  def initialize(agent_run)
    super()
    @agent_run = agent_run
  end

  def name = NAME

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        THEORIES_ARG => {
          "type" => "array", "minItems" => 1, "maxItems" => Chat::Theory::MAX,
          "items" => {
            "type" => "object",
            "properties" => {
              "title" => { "type" => "string", "description" => "The cause, in a short sentence, such as worker's 13:38 deploy raised its database pool" },
              "status" => { "type" => "string", "enum" => Chat::Theory::STATUSES, "description" => "open, confirmed or ruled_out" },
              "evidence" => { "type" => "string", "description" => "The read that settled it and what it showed, or for an open one what would settle it" },
              "leading" => { "type" => "boolean", "description" => "The cause you lead with (optional)" }
            },
            "required" => %w[title status evidence]
          }
        }
      },
      "required" => [ THEORIES_ARG ]
    }
  end

  # The arguments match the schema above, not an execute signature, so skip the base check.
  def call(tool_call: nil, **arguments)
    chat = @agent_run.chat
    return "There is no saved chat to keep a board in." unless chat

    given = Array(arguments.stringify_keys[THEORIES_ARG]).filter_map do |theory|
      theory = theory.to_h.stringify_keys
      next if theory["title"].blank? || Chat::Theory::STATUSES.exclude?(theory["status"].to_s)

      Chat::Theory::Given.new(title: theory["title"], status: theory["status"].to_s, evidence: theory["evidence"], leading: theory["leading"] == true)
    end
    return "Give at least one theory with a title, a status and the evidence." if given.empty?

    self.class.board(Chat::Theory.replace!(chat, given, tool_call_id: tool_call&.id.to_s))
  end

  # The board as Halon reads it back.
  def self.board(theories)
    leading = Chat::Theory.leading_of(theories)
    lines = theories.map do |theory|
      "#{theory.position}. [#{theory.status.tr('_', ' ')}]#{' (leading)' if theory == leading} #{theory.title}#{" Evidence: #{theory.evidence}" if theory.evidence}"
    end
    "Theory board:\n#{lines.join("\n")}"
  end

  # What a person reads on the step.
  def self.shown(arguments)
    count = Array(arguments.to_h.stringify_keys[THEORIES_ARG]).size
    Chat::Tools::Step.new(title: "Theory board", headline: count == 1 ? "1 theory" : "#{count} theories", asked: [],
                          card: Chat::Tools::Card.new(kind: Chat::Tools::CARD_THEORIES, category: nil))
  end
end

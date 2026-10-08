# What a step got back, shown under it once opened. A call that failed or found nothing shows the provider's own words,
# and a call that answered shows how its answer starts, how long it is and the page it came from. Built from what is already kept for the
# call, the tool's answer and its failure kind, and redacted like every answer, so nothing here is a second copy. total
# counts the answer's lines that are not blank and size its characters.
Chat::StepOutcome = Data.define(:kind, :said, :lines, :total, :size, :link)

class Chat::StepOutcome
  # How a failed call is kept, on its tool call and on a run's step. Not found is the provider saying the thing a read
  # named is not there (Integrations::Outcomes), which answers a check rather than breaking it. Refused is one of
  # Firefight's own rules saying no (Integrations::PolicyRefusal), which is final rather than broken.
  FAILURE_ERROR = "error".freeze
  FAILURE_NOT_FOUND = "not_found".freeze
  FAILURE_REFUSED = "refused".freeze
  FAILURE_KINDS = [ FAILURE_ERROR, FAILURE_NOT_FOUND, FAILURE_REFUSED ].freeze

  KIND_ANSWERED = "answered".freeze
  KIND_FAILED = "failed".freeze
  KIND_NOT_FOUND = "not_found".freeze
  KIND_REFUSED = "refused".freeze
  KINDS = [ KIND_ANSWERED, KIND_FAILED, KIND_NOT_FOUND, KIND_REFUSED ].freeze
  FAILURE_SHOWN_AS = { FAILURE_NOT_FOUND => KIND_NOT_FOUND, FAILURE_REFUSED => KIND_REFUSED }.freeze

  # Enough of an answer to see what came back. The whole of it is the model's, and a run's page shows it in full.
  SHOWN_LINES = 4
  LINE_LIMIT = 160
  SAID_LINES = 2
  SAID_LIMIT = 400

  Link = Data.define(:provider, :url)

  def to_h = super.merge(link: link&.to_h)

  FRAME_OPENING = /\A<#{FirefightAi::Evidence::TAG} [^>\n]*>\n/
  FRAME_CLOSING = "\n</#{FirefightAi::Evidence::TAG}>".freeze
  # A result too large to hand over, or cleared to make room, names where the whole of it was kept.
  SAVED_AS = /\A\[[^\]]*\bsaved (?:in full )?as (?<handle>result_\d+)/
  # How a failure is introduced before the provider's own words, a remote server's "Error: " or Firefight's
  # "<action> failed: ".
  INTRODUCED = /\A(?:Error: |[\w.:-]+ failed: )+/
  ERROR_NAME = /\A[A-Z]\w*: (?=\S)/

  # A chat's call, once it has an answer. A call still running, waiting or cancelled has none.
  def self.for_call(call, chat)
    result = call&.result
    return nil unless result

    text = body(result.content)
    kind = kind_of(failed: call.failed, failure_kind: call.failure_kind)
    build(kind, saved_text(chat, text) || text)
  end

  # How a run's step went, without reading what it returned, or nil while it has not finished. A list of steps shows only this.
  def self.kind_for_step(step)
    case step.status
    when Investigation::Step::STATUS_FAILED then kind_of(failed: true, failure_kind: step.failure_kind)
    when Investigation::Step::STATUS_SUCCEEDED then kind_of(failed: step.failure_kind.present?, failure_kind: step.failure_kind)
    end
  end

  # A run's step, once it finished. A step whose call raised keeps its reason apart from what a tool returned, headed by
  # the error's name, which says nothing a person needs.
  def self.for_step(step)
    kind = kind_for_step(step)
    return nil unless kind

    text = step.status == Investigation::Step::STATUS_FAILED ? step.error_summary.to_s.sub(ERROR_NAME, "") : body(step.raw_result || step.compacted_result)
    build(kind, text)
  end

  def self.kind_of(failed:, failure_kind:)
    return KIND_ANSWERED unless failed

    FAILURE_SHOWN_AS.fetch(failure_kind, KIND_FAILED)
  end

  def self.build(kind, text)
    text = Chat::SecretFree.redacted(text)
    return new(kind: kind, said: said(text), lines: [], total: 0, size: 0, link: nil) unless kind == KIND_ANSWERED

    cited = Integrations::SourceLinks.cited_in(text)
    shown = text.lines.map(&:rstrip).reject { |line| line.strip.empty? || (cited && line.strip == cited.line) }
    new(
      kind: kind, said: nil, lines: first_lines(shown),
      total: shown.size, size: text.length, link: (Link.new(provider: cited.provider, url: cited.url) if cited)
    )
  end

  # JSON laid out over many lines starts with nothing but brackets, so it is shown as one line of what it holds.
  def self.first_lines(shown)
    compact = JSON.generate(JSON.parse(shown.join("\n")))
    [ compact.truncate(SHOWN_LINES * LINE_LIMIT) ]
  rescue JSON::ParserError
    shown.first(SHOWN_LINES).map { |line| line.truncate(LINE_LIMIT) }
  end

  # The provider's words, without how they were introduced, on at most two lines.
  def self.said(text)
    words = text.lines.map(&:strip).reject(&:empty?).first(SAID_LINES).join(" ").sub(INTRODUCED, "")
    words.squish.truncate(SAID_LIMIT).presence
  end

  # What the tool said, taken out of the frame it was handed to the model in. A refusal or a wait is never framed.
  def self.body(content)
    text = content.to_s
    opening = text.match(FRAME_OPENING)
    return text unless opening

    text[opening.end(0)..].split(FRAME_CLOSING, 2).first.to_s
  end

  def self.saved_text(chat, text)
    handle = text.match(SAVED_AS)&.[](:handle)
    handle && chat&.saved_results&.find_by(handle: handle)&.content
  end
  private_class_method :build, :first_lines, :said, :body, :saved_text
end

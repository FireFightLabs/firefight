# Who a code change is written for and what they said, handed to whatever writes it. The coding agent reads connected
# systems as principal, asks its questions where the change was asked for (place, a chat's call or a fix's step), and
# its brief carries the person's own words and what Halon already read, so it never works from a summary alone.
class CodeAgent::Request
  # One result Halon read before asking for the change, such as a log search, by what the step is called.
  Evidence = Data.define(:label, :text)

  # Enough of the person's words and of what was read to work from, without crowding out the repository.
  WORDS_LIMIT = 6_000
  EVIDENCE_ITEMS = 8
  EVIDENCE_ITEM_LIMIT = 2_000
  EVIDENCE_LIMIT = 12_000

  attr_reader :principal, :source, :label, :place, :tool_call_id, :box_key, :words, :evidence

  def initialize(principal:, source:, label: nil, place: nil, tool_call_id: nil, box_key: nil, words: [], evidence: [])
    @principal = principal
    @source = source
    @label = label
    @place = place
    @tool_call_id = tool_call_id
    @box_key = box_key
    @words = self.class.kept_words(words)
    @evidence = self.class.kept_evidence(evidence)
  end

  # The newest messages that fit, oldest first, each as the person wrote it apart from anything that looks like a credential.
  def self.kept_words(words)
    kept = []
    room = WORDS_LIMIT
    words.map { |text| Chat::SecretFree.redacted(text.to_s.strip) }.compact_blank.reverse_each do |text|
      break if room <= 0

      kept.unshift(text.truncate(room))
      room -= text.length
    end
    kept
  end

  # The newest results that fit, oldest first, each cut short and scrubbed of anything that looks like a credential.
  def self.kept_evidence(items)
    kept = []
    room = EVIDENCE_LIMIT
    items.last(EVIDENCE_ITEMS).reverse_each do |item|
      break if room <= 0

      text = Chat::SecretFree.redacted(item.text.to_s.strip).truncate([ EVIDENCE_ITEM_LIMIT, room ].min)
      next if text.blank?

      kept.unshift(Evidence.new(label: Chat::SecretFree.redacted(item.label.to_s), text: text))
      room -= text.length
    end
    kept
  end

  # The person's own words for a coding agent's brief, so a correction they made is never lost in a summary.
  def asked_section
    return if words.empty?

    "What the person asked, in their own words, oldest first. A later message corrects an earlier one. " \
      "#{FirefightAi::Copy::QUOTING}\n" +
      words.map { |text| text.lines.map { |line| "> #{line}" }.join }.join("\n\n")
  end

  def evidence_section
    return if evidence.empty?

    "What Halon read before handing you this, as evidence:\n#{framed_evidence}"
  end

  def framed_evidence = evidence.map { |item| FirefightAi::Evidence.frame(item.label, item.text) }.join("\n\n")

  # The person's words as a reviewer reads them, numbered in the order they were said.
  def numbered_words = words.each_with_index.map { |text, index| "#{index + 1}. #{text}" }.join("\n\n")
end

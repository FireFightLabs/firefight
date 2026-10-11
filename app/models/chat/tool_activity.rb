# What a long tool said about how far it got while it worked (RubyLLM::Tool#progress), such as "2 of 3 checks reported",
# shown under its step in a dashboard chat while it runs. value and total count the work in the tool's own unit, nil when
# it says only a sentence. A sentence can come from a coding agent or a script, so a credential is taken out of it.
Chat::ToolActivity = Data.define(:message, :value, :total) do
  def self.from(progress)
    message = Chat::SecretFree.redacted(progress.message.to_s.squish).truncate(Chat::ToolActivity::MESSAGE_LIMIT).presence
    value = progress.value&.to_i
    total = progress.total&.to_i
    new(message: message, value: value, total: (total if total&.positive?))
  end

  def empty? = message.nil? && value.nil?

  # What a Chat::CodeFixProgress::Pace compares, so the same report is never sent twice and news goes at most once a beat.
  def signature = [ message, value, total ]

  # A tool's last word is its answer, which ends the step, so a report never forces its way past the pace.
  def finished? = false

  def to_h = { message: message, value: value, total: total }
end

Chat::ToolActivity.const_set(:MESSAGE_LIMIT, 160)

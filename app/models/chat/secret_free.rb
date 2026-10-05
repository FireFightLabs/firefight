# Text that reaches every later prompt, a memory or instructions, refuses anything that looks like a credential. The
# patterns are the transcript scrubber's, plus a connection string carrying a password.
module Chat::SecretFree
  extend ActiveSupport::Concern

  CREDENTIAL_URL = %r{\b[a-z][a-z0-9+.-]*://[^\s:@/]+:[^\s@/]+@}i
  SECRET_PATTERNS = IncidentTranscriptMessage::Scrubbing::SECRET_PATTERNS.merge(credential_url: CREDENTIAL_URL).freeze

  included do
    validate :holds_no_secret
  end

  # The text with anything that looks like a credential replaced by a marker naming what it was, such as
  # [REDACTED:github_token]. Every provider's answer passes through it before the model, a chat or MCP reads it.
  def self.redacted(text) = SECRET_PATTERNS.reduce(text.to_s) { |kept, (name, pattern)| kept.gsub(pattern, "[REDACTED:#{name}]") }

  private

  def holds_no_secret
    found = SECRET_PATTERNS.keys.find { |name| text.to_s.match?(SECRET_PATTERNS[name]) }
    errors.add(:text, "looks like it holds a secret (#{found.to_s.humanize(capitalize: false)}), so it is not saved") if found
  end
end

module Integrations
  # A provider's own words joined to Firefight's into sentences a person reads, so a reason that ends in a period never
  # makes "..", and one that joins clauses with semicolons reads as separate sentences.
  module Sentence
    # "<lead>: <reason>." with the reason's first line, trimmed, ended once, or the lead alone as a sentence when the
    # provider gave no reason. after is a sentence that follows, such as what to do.
    def self.join(lead, reason, after: nil)
      said = clean(reason)
      [ ended(said ? "#{lead.to_s.strip}: #{said}" : lead.to_s.strip), after.present? ? ended(after.to_s.strip) : nil ].compact.join(" ")
    end

    # A provider's reason as a clause, its first line, without a closing period and with semicolons as commas. nil when
    # there is nothing to say.
    def self.clean(reason)
      line = reason.is_a?(Exception) ? reason.message : reason
      line.to_s.lines.first.to_s.strip.gsub(/\s*;\s*/, ", ").sub(/[.\s]+\z/, "").presence
    end

    # A provider's reason as a sentence of its own, ended once, or nil when there is nothing to say.
    def self.of(reason) = clean(reason)&.then { |said| ended(said) }

    # Sentences one after another, each ended once and the empty ones left out, so a provider that gave no reason leaves
    # no stray space before Firefight's own words.
    def self.all(*parts) = parts.filter_map { |part| of(part) }.join(" ")

    # The text ended with one period, unless it already ends in a question or exclamation mark.
    def self.ended(text) = text.match?(/[.!?]\z/) ? text : "#{text}."
  end
end

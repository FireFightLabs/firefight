# Slack silently appends a period to hint text, so an unnormalized description renders
# differently there than in the dashboard. Normalizing on save makes Slack's rewrite a no-op.
module NormalizedDescription
  extend ActiveSupport::Concern

  TERMINATORS = [ ".", "!", "?" ].freeze

  included do
    before_validation :normalize_description
  end

  class_methods do
    def normalize_description(text)
      trimmed = text.to_s.strip
      return text if trimmed.blank?

      # A first word with its own capitalization is left alone, so iOS survives.
      first_word = trimmed[/\A\S+/]
      trimmed = trimmed.sub(/\A./, &:upcase) if first_word == first_word.downcase
      trimmed += "." unless trimmed.end_with?(*TERMINATORS)
      trimmed
    end
  end

  private

  def normalize_description
    return unless has_attribute?(:description) && description_changed?

    self.description = self.class.normalize_description(description)
  end
end

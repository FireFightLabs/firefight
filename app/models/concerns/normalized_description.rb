# Stores option descriptions as finished sentences so every surface renders the
# same string.
#
# Slack silently appends a period to `hint` text on an input block when one is
# missing, and leaves it alone when one is already there. That is undocumented
# but consistent, so a description typed as "limited impact" reaches Slack as
# "Limited impact." while the dashboard, the public API and the MCP tools show
# the raw value. Normalizing on save makes Slack's own rewrite a no-op.
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

      # A first word that carries its own capitalization is left alone, so iOS
      # and eBay survive. An all-lowercase one is capitalized, which does catch
      # tool names like kubectl.
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

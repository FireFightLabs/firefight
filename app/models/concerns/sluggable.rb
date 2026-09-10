# Lookups by the slug a name would produce must use slug_for. A second
# derivation that drifts creates duplicates instead of finding the row.
module Sluggable
  extend ActiveSupport::Concern

  included do
    before_validation :derive_slug, on: :create
  end

  class_methods do
    # parameterize keeps hyphens, which the slug format rejects.
    def slug_for(name)
      name.to_s.parameterize(separator: "_").tr("-", "_")
    end
  end

  # Custom fields and runbooks were minted with this rule, so they must keep
  # deriving with it or lookups stop finding the stored row.
  def self.word_slug(name)
    name.to_s.strip.downcase.gsub(/\s+/, "_").gsub(/[^a-z0-9_]/, "")
  end

  private

  def derive_slug
    self.slug = self.class.slug_for(name) if slug.blank?
  end
end

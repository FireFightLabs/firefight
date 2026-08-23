# A name-derived, immutable-by-convention slug. One rule, one place, callers
# that need to look a record up by the slug a name *would* produce must use
# `slug_for` rather than repeating the derivation, or a drift between the two
# silently creates duplicates instead of finding the existing row.
module Sluggable
  extend ActiveSupport::Concern

  included do
    before_validation :derive_slug, on: :create
  end

  class_methods do
    # parameterize keeps hyphens, which the slug format rejects, so a name
    # like "Database read-only" has to lose them here.
    def slug_for(name)
      name.to_s.parameterize(separator: "_").tr("-", "_")
    end
  end

  private

  def derive_slug
    self.slug = self.class.slug_for(name) if slug.blank?
  end
end

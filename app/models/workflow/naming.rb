# A workflow is found by its slug, its name or one of its other names, whatever the case, as a runbook is, so a person
# or Halon can name it the way they say it.
module Workflow::Naming
  extend ActiveSupport::Concern

  ALIAS_LIMIT = Runbook::Procedure::ALIAS_LIMIT

  included do
    before_validation :tidy_names
    before_validation :assign_slug, on: :create
  end

  class_methods do
    def named(scope, text)
      wanted = text.to_s.squish.downcase
      return if wanted.empty?

      scope.find_by(slug: wanted) || scope.find_by("LOWER(#{table_name}.name) = ?", wanted) ||
        scope.find_by("EXISTS (SELECT 1 FROM unnest(#{table_name}.aliases) AS other WHERE LOWER(other) = ?)", wanted)
    end
  end

  private

  def tidy_names
    self.name = name.to_s.squish.presence
    self.aliases = Array(aliases).map { |other| other.to_s.squish }.compact_blank.uniq(&:downcase).first(ALIAS_LIMIT)
  end

  def assign_slug
    self.slug = Sluggable.word_slug(name) if slug.blank?
  end
end

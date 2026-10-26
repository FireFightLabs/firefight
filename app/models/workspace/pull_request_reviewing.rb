# Which pull requests Halon reviews. It always reviews one when someone asks, by adding Firefight as a reviewer or in a
# comment, and its own after they open. An admin can also have it review every pull request when it opens, in every
# repository its code hosts reach or only the ones chosen, named as owner/name the way the resource map holds them.
module Workspace::PullRequestReviewing
  extend ActiveSupport::Concern

  ON_OPEN_OFF = "off".freeze
  ON_OPEN_ALL = "all".freeze
  ON_OPEN_CHOSEN = "chosen".freeze
  ON_OPEN_CHOICES = [ ON_OPEN_OFF, ON_OPEN_ALL, ON_OPEN_CHOSEN ].freeze
  CHOSEN_NEEDS_ONE = "Choose at least one repository, or review pull requests in every repository.".freeze

  included do
    normalizes :pull_request_review_repositories, with: ->(names) { Array(names).filter_map { |name| name.to_s.strip.downcase.presence }.uniq.sort }
    validates :pull_request_reviews_on_open, inclusion: { in: ON_OPEN_CHOICES }
    validate :chosen_repositories_given
  end

  # Whether a pull request that just opened in a repository is reviewed without anyone asking.
  def reviews_on_open?(repository)
    case pull_request_reviews_on_open
    when ON_OPEN_ALL then true
    when ON_OPEN_CHOSEN then pull_request_review_repositories.include?(repository.to_s.downcase)
    else false
    end
  end

  # The repositories the workspace's code hosts put on the map, which the settings page offers to choose from, with any
  # chosen one the map no longer holds so it can be taken off.
  def reviewable_repositories
    held = ResourceMap::Resource.present.where(workspace_id: id, kind: ResourceMap::KIND_REPOSITORY).distinct.pluck(:external_id).map(&:downcase)
    (held + pull_request_review_repositories).uniq.sort
  end

  # Grants Halon's review agent the tools a code host connection posts a review and reads a fix through, and nothing
  # more, through the same grants the Permissions screen writes, for a connection made before the agent existed. A
  # connection made since is granted each tool as it is minted (Integration::Tool).
  def grant_pull_request_reviewing!(integration)
    integration.tools.available.where(name: Integrations::PullRequestReviews.tools(integration.provider)).find_each do |tool|
      Ability::Grant.grant!(workspace: self, principal: SystemAgent.pull_request_review, target: { action: tool.ability_action || tool.sync_ability_action! })
    end
  end

  # What the toast says once the setting changed.
  def pull_request_reviews_on_open_words
    case pull_request_reviews_on_open
    when ON_OPEN_ALL then "Halon now reviews every pull request when it opens."
    when ON_OPEN_CHOSEN
      count = pull_request_review_repositories.size
      "Halon now reviews every pull request when it opens in #{count} #{'repository'.pluralize(count)}."
    else "Halon now reviews a pull request only when someone asks."
    end
  end

  private

  def chosen_repositories_given
    return unless pull_request_reviews_on_open == ON_OPEN_CHOSEN && pull_request_review_repositories.empty?

    errors.add(:pull_request_review_repositories, CHOSEN_NEEDS_ONE)
  end
end

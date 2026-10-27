# A review's own reads of the pull request, its files and its head, which no tool makes. They read the connection, so
# Halon needs its read pack as it would for a read through one of its tools, and taking the pack away stops reviews.
# Asked when a review starts and each time a worker takes it, and in the activity log under the review either way.
module PullRequestReview::Reading
  extend ActiveSupport::Concern

  # Halon no longer holds the read pack of the connection the review reads through.
  class NotAllowed < StandardError; end

  class_methods do
    # Runs the block as one read of row's connection. Raises NotAllowed before the block runs when Halon may not read it.
    def reading!(row, repository:, number:, &)
      AbilityGateway.authorize_connection_read!(
        principal: SystemAgent.investigator, integration: row.integration, params: { "repository" => repository, "number" => number },
        context: { source: AbilityGateway::SOURCE_PULL_REQUEST_REVIEW, triggered_by_label: activity_label(repository, number) }, &
      )
    rescue AbilityGateway::Denied
      raise NotAllowed
    end

    # How the activity log names what a review was for.
    def activity_label(repository, number) = "Review of PR ##{number} in #{repository}"
  end
end

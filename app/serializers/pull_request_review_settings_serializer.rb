class PullRequestReviewSettingsSerializer < BaseSerializer
  object_as :workspace

  attributes(
    pull_request_reviews_on_open: { type: :string },
    pull_request_review_repositories: { type: "string[]" }
  )

  # Every repository the workspace's code hosts put on the map, and any chosen one the map no longer holds.
  type "string[]"
  def repositories = workspace.reviewable_repositories
end

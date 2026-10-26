# Starts Halon's review of a pull request at its head now, through the code host connection whose map holds the
# repository, and queues it for a worker. A pull request already under review answers the review that is running. A
# review spends at most what the workspace lets one of Halon's runs spend. Posting what it found is not done here.
class PullRequestReview::Start
  # Why a review cannot start, in a sentence for whoever asked.
  class Refused < StandardError; end

  NOT_HELD = "No code host connected to this workspace holds %<repository>s on its resource map, so Halon cannot read it.".freeze

  def self.call(workspace:, repository:, number:, trigger:, row: nil)
    new(workspace: workspace, repository: repository, number: number, trigger: trigger, row: row).call
  end

  def initialize(workspace:, repository:, number:, trigger:, row: nil)
    @workspace = workspace
    @repository = repository
    @number = number
    @trigger = trigger
    @row = row
  end

  def call
    unavailable = Investigation.unavailable_reason(@workspace)
    raise Refused, unavailable if unavailable

    row = @row || Integrations::ReviewHost.row_for(@workspace, @repository)
    raise Refused, format(NOT_HELD, repository: @repository) unless row

    pull = Integrations::ReviewHost.pull_request(row, repository: @repository, number: @number)
    review = PullRequestReview.create!(
      workspace: @workspace, integration_environment: row, repository: @repository, number: @number, title: pull.title, url: pull.url,
      base_ref: pull.base_ref, base_sha: pull.base_sha, head_ref: pull.head_ref, head_sha: pull.head_sha, trigger: @trigger,
      max_spend_cents: @workspace.investigation_limits.max_spend_cents
    )
    ActiveRecord.after_all_transactions_commit { PullRequestReviewJob.perform_later(review.id) }
    review
  rescue ActiveRecord::RecordNotUnique
    @workspace.pull_request_reviews.live.seen.of_pull_request(@repository, @number).first!
  end
end

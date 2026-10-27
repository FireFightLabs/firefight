# Starts Halon's review of a pull request at its head now, through the code host connection whose map holds the
# repository, and queues it for a worker. A pull request already under review answers the review that is running. A
# review spends at most what the workspace lets one of Halon's runs spend (PullRequestReview.request!). Posting what it
# found is not done here.
class PullRequestReview::Start
  # Why a review cannot start, in a sentence for whoever asked, and which of PullRequestReview::Refusal::REASONS it is, so
  # the pull request can be told in words of its own.
  class Refused < StandardError
    attr_reader :reason

    def initialize(message = nil, reason: nil)
      super(message)
      @reason = reason
    end
  end

  NOT_HELD = "No code host connected to this workspace holds %<repository>s on its resource map, so Halon cannot read it.".freeze
  NOT_ALLOWED = "Halon has no access to read %<connection>s, so it cannot review this pull request.".freeze

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
    raise Refused.new(unavailable, reason: unavailable == Investigation::MODEL_NOT_SET_UP ? PullRequestReview::Refusal::MODEL_NOT_SET_UP : PullRequestReview::Refusal::HALON_UNAVAILABLE) if unavailable

    row = @row || Integrations::ReviewHost.row_for(@workspace, @repository)
    raise Refused.new(format(NOT_HELD, repository: @repository), reason: PullRequestReview::Refusal::NO_CONNECTION) unless row

    pull = head(row)
    PullRequestReview.request!(row, repository: @repository, number: @number, head_sha: pull.head_sha, trigger: @trigger, title: pull.title, url: pull.url,
                                    base_ref: pull.base_ref, base_sha: pull.base_sha, head_ref: pull.head_ref)
  end

  private

  # The pull request as its host shows it now, read as Halon, which needs the connection's read pack.
  def head(row)
    PullRequestReview.reading!(row, repository: @repository, number: @number) do
      Integrations::ReviewHost.pull_request(row, repository: @repository, number: @number)
    end
  rescue PullRequestReview::Reading::NotAllowed
    raise Refused.new(format(NOT_ALLOWED, connection: row.integration.display_name), reason: PullRequestReview::Refusal::NO_ACCESS)
  end
end

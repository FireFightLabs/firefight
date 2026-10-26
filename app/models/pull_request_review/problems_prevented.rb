# The problems Halon's reviews prevented in one workspace over a window: findings that were serious, or major or worse,
# and fixed before their pull request merged. Each counts in the window its pull request merged in, since merging with
# the fix in is the moment the problem was kept out. Newest merge first, a page at a time, so every one can be opened.
class PullRequestReview::ProblemsPrevented
  PER_PAGE = 5

  attr_reader :days

  def initialize(workspace, days: Investigation::Performance::DEFAULT_WINDOW)
    @workspace = workspace
    @days = Investigation::Performance::WINDOWS.include?(days.to_i) ? days.to_i : Investigation::Performance::DEFAULT_WINDOW
  end

  def since = @since ||= days.days.ago.beginning_of_day

  def count = @count ||= findings.count

  # One page of problems. A row over the page says whether another follows, without counting again.
  def page(number, per_page: PER_PAGE)
    number = [ number.to_i, 1 ].max
    rows = findings.includes(:review).reorder("pull_request_reviews.merged_at DESC", "pull_request_reviews.id", "pull_request_review_findings.position")
                   .offset((number - 1) * per_page).limit(per_page + 1).to_a
    Page.new(number: number, problems: rows.first(per_page), next_page: rows.size > per_page ? number + 1 : nil)
  end

  Page = Data.define(:number, :problems, :next_page) do
    def previous_page = number > 1 ? number - 1 : nil
  end

  private

  def findings
    PullRequestReview::Finding.prevented.where(pull_request_reviews: { workspace_id: @workspace.id, merged_at: since.. })
  end
end

# One pull request review with every finding in full: its failure chain and the evidence behind it. A review on a public
# repository links here instead of naming its evidence on the pull request, so only the workspace's own people read it.
# A resource on the map a viewer cannot reach is left out of what they see.
class HalonPullRequestReviewPagesController < InertiaController
  authorizes Ability::Action::RESOURCE_INVESTIGATIONS, read: %i[show]

  include RequiresAgent
  before_action :require_agent!

  def show
    review = current_workspace.pull_request_reviews.seen.find(params[:id])
    findings = review.findings.includes(:review).to_a
    render inertia: "halon/pull-request-review", props: {
      review: PullRequestReviewPageSerializer.one(review),
      findings: PullRequestReviewFindingSerializer.many(findings, reachable: PullRequestReview::Evidence.reachable(findings, current_membership))
    }
  end
end

# Which pull requests Halon reviews. Someone asking always works, and an admin can have it review every pull request when
# it opens, in every repository or the ones chosen.
class HalonPullRequestReviewsController < InertiaController
  authorizes Ability::Action::RESOURCE_WORKSPACE, read: :show, update: :update

  def show
    render inertia: "halon/pull-request-reviews", props: {
      settings: PullRequestReviewSettingsSerializer.one(current_workspace),
      hosts: Integrations::PullRequestReviews.host_names(current_workspace)
    }
  end

  def update
    given = params.permit(:pull_request_reviews_on_open, pull_request_review_repositories: [])
    given[:pull_request_review_repositories] ||= [] if params.key?(:pull_request_reviews_on_open)
    current_workspace.update_settings!(given)
    redirect_to halon_pull_request_reviews_path, notice: current_workspace.pull_request_reviews_on_open_words
  rescue ActiveRecord::RecordInvalid => e
    redirect_to halon_pull_request_reviews_path, inertia: { errors: e.record.errors.to_hash }
  end
end

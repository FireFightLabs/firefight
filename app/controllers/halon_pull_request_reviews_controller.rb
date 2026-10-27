# Which pull requests Halon reviews. Someone asking always works, and an admin can have it review every pull request when
# it opens, in every repository or the ones chosen. The chosen ones are kept when another choice is made, so choosing
# them again brings them back.
class HalonPullRequestReviewsController < InertiaController
  authorizes Ability::Action::RESOURCE_WORKSPACE, read: :show, update: :update

  def show
    render inertia: "halon/pull-request-reviews", props: {
      settings: PullRequestReviewSettingsSerializer.one(current_workspace),
      hosts: Integrations::PullRequestReviews.host_names(current_workspace),
      providers: Integrations::PullRequestReviews.provider_names
    }
  end

  def update
    current_workspace.update_settings!(params.permit(:pull_request_reviews_on_open, pull_request_review_repositories: []))
    redirect_to halon_pull_request_reviews_path, notice: current_workspace.pull_request_reviews_on_open_words
  rescue ActiveRecord::RecordInvalid => error
    redirect_to halon_pull_request_reviews_path, inertia: { errors: error.record.errors.to_hash }
  end
end

class ProfilesController < InertiaController
  def show
    identities = current_user.identities.sort_by(&:created_at)
    render inertia: "profile/index", props: {
      signInMethods: SignInMethodSerializer.many(identities)
    }
  end
end

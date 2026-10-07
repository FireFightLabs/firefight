# A person removing one of their own ways to sign in. Their own account only, so no workspace grant is involved.
class UserIdentitiesController < InertiaController
  def destroy
    identity = current_user.identities.find(params[:id])
    identity.remove!
    redirect_to profile_path, notice: "#{identity.description} was removed from your sign-in methods."
  rescue ActiveRecord::RecordNotDestroyed => e
    redirect_to profile_path, alert: e.message
  end
end

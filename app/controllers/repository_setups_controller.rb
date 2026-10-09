# How each repository a code host connection holds is set up before its tests, under the connection's Code changes: read
# from its CI, set up or changed by hand, read from CI again and cleared. A refusal from a dialog stays beside what was
# typed, and the connection's details stay open either way.
class RepositorySetupsController < InertiaController
  authorizes Ability::Action::RESOURCE_INTEGRATIONS, update: %i[create update derive destroy]
  before_action :set_integration
  before_action :set_setup, only: %i[update derive destroy]

  # A repository's setup read from its CI, or set up by hand when read_from_ci is not given.
  def create
    repository = params[:repository].to_s.strip
    refusal = @integration.repository_setup_blocked_reason(repository)
    return refused(repository: refusal) if refusal
    return read_from_ci(repository) if ActiveModel::Type::Boolean.new.cast(params[:read_from_ci])

    setup = @integration.repository_setups.new(workspace: current_workspace, repository: repository)
    refusal = setup.change!(**setup_params)
    return refused(setup: refusal) if refusal

    redirect_to details, notice: saved_words(setup)
  end

  def update
    refusal = @setup.change!(**setup_params)
    return refused(setup: refusal) if refusal

    redirect_to details, notice: saved_words(@setup)
  end

  # Reads it from the repository's CI again, replacing what is kept, changes made here included.
  def derive
    refusal = @integration.ci_read_blocked_reason
    return redirect_to details, alert: refusal if refusal

    setup = Integrations::CiSetup.derive!(@integration.resolve_environment(nil), @setup.repository)
    redirect_to details, notice: @integration.repository_setup_read_words(setup)
  rescue Integrations::CiSetup::Missing => error
    redirect_to details, alert: "Could not read #{@setup.repository}'s setup from CI. #{error.message}"
  rescue Integrations::Error => error
    redirect_to details, alert: ci_unreachable(@setup.repository, error)
  end

  def destroy
    @setup.destroy!
    redirect_to details, notice: "Cleared #{@setup.repository}'s setup. Halon reads it from CI again the next time it prepares #{@setup.repository}."
  end

  private

  def read_from_ci(repository)
    refusal = @integration.ci_read_blocked_reason
    return refused(repository: refusal) if refusal

    setup = Integrations::CiSetup.derive!(@integration.resolve_environment(nil), repository)
    redirect_to details, notice: @integration.repository_setup_read_words(setup)
  rescue Integrations::CiSetup::Missing => error
    refused(repository: error.message)
  rescue Integrations::Error => error
    refused(repository: ci_unreachable(repository, error))
  end

  # A transport error's words are for the log, so a person reads a plain sentence.
  def ci_unreachable(repository, error)
    Rails.logger.warn({ event: "repository_setup.ci_read_failed", integration_id: @integration.id, repository: repository,
                        error: Chat::SecretFree.redacted(error.message) }.to_json)
    "Could not reach the code host to read #{repository}'s CI. Try again in a moment."
  end

  # Variables arrive as name and value pairs, so one named twice is refused rather than kept once.
  def setup_params
    given = params.permit(commands: [], env: %i[name value], services: [ :name, :image, :port, { env: %i[name value] } ])
    { services: Array(given[:services]).map(&:to_h), env: Array(given[:env]).map(&:to_h), commands: Array(given[:commands]) }
  end

  def saved_words(setup) = "Saved how #{setup.repository} is set up before its tests."

  def refused(errors) = redirect_to(details, inertia: { errors: errors })

  def details = integrations_path(Integration::DETAILS_QUERY_PARAM => @integration.id)

  def set_integration
    @integration = current_workspace.integrations.where(deleted_at: nil).find(params[:integration_id])
  end

  def set_setup
    @setup = @integration.repository_setups.find(params[:id])
  end
end

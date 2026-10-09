# The setup checklist after the founder's letter. An admin works through it in order and cannot leave it for another
# page until it is done (ContinuesSetup). Anyone else is sent to the dashboard. Each answer is kept on the workspace's
# onboarding row, and the last one finishes setup and opens the dashboard.
class SetupController < InertiaController
  include AiAccountProps

  DONE = "Setup is done. Welcome to Firefight.".freeze
  AI_CHOSEN = {
    WorkspaceOnboarding::AI_ACCOUNT => "Halon will use your own AI account.",
    WorkspaceOnboarding::AI_CREDITS => "Halon will use your Firefight credits.",
    WorkspaceOnboarding::AI_HOUSE => "Halon will use the AI keys this Firefight runs on."
  }.freeze

  authorizes Ability::Action::RESOURCE_WORKSPACE, read: :show, update: %i[choose_ai answer_category review_permissions skip_slack]

  skip_before_action :continue_setup
  before_action :set_onboarding

  def show
    return redirect_to(dashboard_path) if @onboarding.finish_if_done!

    render inertia: "setup/index", props: {
      workspaceName: current_workspace.name,
      email: current_user.email,
      steps: OnboardingStepSerializer.many(@onboarding.steps),
      aiChoice: @onboarding.ai_choice,
      # Each choice offered here, with why it cannot be chosen yet, or nil.
      aiChoices: @onboarding.ai_choices.index_with { |choice| @onboarding.ai_choice_blocked_reason(choice) },
      **ai_account_props,
      categories: OnboardingCategorySerializer.many(@onboarding.stack_cards),
      stackAnswers: @onboarding.stack_answers,
      environments: EnvironmentOptionSerializer.many(current_workspace.environment_entries),
      principals: PrincipalSerializer.many(Ability::Principal.all(current_workspace)),
      packs: AbilityRoleSerializer.many(current_workspace.ability_roles.built_in.order(:name).with_holder_counts.includes(:grants, :role_actions, :integration)),
      firstQuestion: @onboarding.first_question,
      walkthrough: WorkspaceOnboarding::STEPS
    }
  end

  def choose_ai
    choice = params[:choice].to_s
    return back(alert: "Pick how Halon pays for its AI.") unless @onboarding.ai_choices.include?(choice)

    blocked = @onboarding.ai_choice_blocked_reason(choice)
    return back(alert: blocked) if blocked

    @onboarding.choose_ai!(choice)
    advance(AI_CHOSEN.fetch(choice))
  end

  def answer_category
    card = @onboarding.stack_cards.find { |candidate| candidate.category.slug == params[:category] }
    answer = params[:answer].to_s
    return back(alert: "That is not a category of integrations.") unless card
    return back(alert: "Connect a tool or say you don't use any.") unless WorkspaceOnboarding::ANSWERS.include?(answer)

    blocked = WorkspaceOnboarding.category_answer_blocked_reason(card, answer)
    return back(alert: blocked) if blocked

    @onboarding.answer_category!(card.category, answer)
    advance(answer == WorkspaceOnboarding::ANSWER_CONNECTED ? "#{card.category.name} is set." : "#{card.category.name} skipped.")
  end

  def review_permissions
    @onboarding.review_permissions!
    advance("Permissions are set. Change them any time under Permissions.")
  end

  def skip_slack
    @onboarding.skip_slack!
    advance("Slack can wait. Connect it from the banner at the top of any page.")
  end

  private

  # Setup belongs to a workspace that has one and to whoever it steers, so anyone else goes on to the dashboard.
  def set_onboarding
    @onboarding = current_workspace.onboarding
    redirect_to dashboard_path unless @onboarding&.steers?(current_membership)
  end

  def back(alert:)
    redirect_to onboarding_checklist_path, alert: alert
  end

  # The answer that finishes setup opens the dashboard.
  def advance(notice)
    return redirect_to(dashboard_path, notice: DONE) if @onboarding.finish_if_done!

    redirect_to onboarding_checklist_path, notice: notice
  end
end

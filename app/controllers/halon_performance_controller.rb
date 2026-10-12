# How Halon has done for this workspace, for every member, since trust in an agent grows from seeing its record.
class HalonPerformanceController < InertiaController
  authorizes Ability::Action::RESOURCE_INVESTIGATIONS, read: %i[show]

  include RequiresAgent
  include PlatformText
  before_action :require_agent!

  def show
    performance = Investigation::Performance.new(current_workspace, days: params[:days])

    render inertia: "halon/performance", props: {
      performance: HalonPerformanceSerializer.one(performance, platform_texts: platform_texts(asked_in_platform(performance))),
      windows: Investigation::Performance::WINDOWS
    }
  end

  private

  def asked_in_platform(performance)
    performance.mistakes.map { |mistake| mistake.finding.investigation }.select(&:question_in_platform_markup?).map(&:question)
  end
end

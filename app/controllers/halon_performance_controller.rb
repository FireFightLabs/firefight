# How Halon has done for this workspace, for every member, since trust in an agent grows from seeing its record.
class HalonPerformanceController < InertiaController
  authorizes Ability::Action::RESOURCE_INVESTIGATIONS, read: %i[show]

  include RequiresAgent
  include PlatformText
  before_action :require_agent!

  PREVENTED_PAGE_PARAM = "prevented_page"
  PROP_PREVENTED = "prevented"
  PROP_PREVENTED_COUNT = "preventedCount"
  PROPS = { "PREVENTED" => PROP_PREVENTED, "PREVENTED_COUNT" => PROP_PREVENTED_COUNT }.freeze

  def show
    performance = Investigation::Performance.new(current_workspace, days: params[:days])
    prevented = PullRequestReview::ProblemsPrevented.new(current_workspace, days: performance.days)

    render inertia: "halon/performance", props: {
      performance: HalonPerformanceSerializer.one(performance, platform_texts: platform_texts(asked_in_platform(performance))),
      windows: Investigation::Performance::WINDOWS,
      PROP_PREVENTED_COUNT => prevented.count,
      PROP_PREVENTED => InertiaRails.scroll(-> { prevented_page_metadata(prevented) }) { HalonPreventedProblemSerializer.many(prevented_page(prevented).problems) }
    }
  end

  private

  def asked_in_platform(performance)
    performance.mistakes.map { |mistake| mistake.finding.investigation }.select(&:question_in_platform_markup?).map(&:question)
  end

  def prevented_page(prevented) = @prevented_page ||= prevented.page(params[PREVENTED_PAGE_PARAM])

  def prevented_page_metadata(prevented)
    page = prevented_page(prevented)
    { page_name: PREVENTED_PAGE_PARAM, current_page: page.number, previous_page: page.previous_page, next_page: page.next_page }
  end
end

module Operator
  # The console's home page. Lists what needs attention, then summary numbers for each area.
  class OverviewController < BaseController
    def show
      jobs = JobHealth.read(since: filter.since)
      overview = Overview.new(filter, jobs: jobs)
      attention = Attention.new(filter, jobs: jobs)

      render inertia: "operator/overview", props: {
        attentionItems: AttentionItemSerializer.many(attention.items),
        attentionCapped: attention.capped_kinds.any?,
        attentionLimit: Attention::PER_KIND,
        incidents: camelized(overview.incidents),
        workflows: camelized(overview.workflows),
        jobs: camelized(overview.jobs),
        halon: camelized(overview.halon),
        **filter_props
      }
    end
  end
end

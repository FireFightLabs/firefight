module Operator
  # The console's front page: what needs a person, then each process in numbers, for one window and workspace.
  class OverviewController < BaseController
    def show
      jobs = JobHealth.read(since: filter.since)
      overview = Overview.new(filter, jobs: jobs)

      render inertia: "operator/overview", props: {
        attentionItems: OperatorAttentionItemSerializer.many(Attention.new(filter, jobs: jobs).items),
        incidents: camelized(overview.incidents),
        workflows: camelized(overview.workflows),
        jobs: camelized(overview.jobs),
        halon: camelized(overview.halon),
        **filter_props
      }
    end
  end
end

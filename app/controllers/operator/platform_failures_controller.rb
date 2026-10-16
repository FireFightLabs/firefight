module Operator
  # One failed platform call and every recent time the same call failed the same way, in the same workspace and channel.
  class PlatformFailuresController < BaseController
    def show
      failure = PlatformCallFailure.includes(:workspace).find(params[:id])
      alike = PlatformFailures.alike(failure)
      occurrences = alike.includes(:workspace).limit(PlatformFailures::OCCURRENCES_LIMIT).to_a
      incidents = PlatformFailures.incidents_for(occurrences)
      detail = PlatformFailureDetailSerializer::Detail.new(failure, PlatformFailures.reason(failure), alike.minimum(:created_at))

      render inertia: "operator/platform-failures/show", props: {
        failure: PlatformFailureDetailSerializer.one(detail),
        total: alike.count,
        occurrences: PlatformFailureSerializer.many(occurrences.map { |occurrence| PlatformFailureSerializer::Row.new(occurrence, incidents[[ occurrence.workspace_id, occurrence.channel_id ]]) })
      }
    end
  end
end

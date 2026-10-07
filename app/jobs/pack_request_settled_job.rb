# Redraws a pack request's messages once the pack was given on the Permissions screen rather than from the request.
class PackRequestSettledJob < ApplicationJob
  queue_as :default

  def perform(pack_request_id)
    request = Ability::PackRequest.find_by(id: pack_request_id)
    PackRequestService.settled!(request) if request
  end
end

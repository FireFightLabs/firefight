# Applies what an on-call tool's webhook said happened to a page, such as someone acknowledging it there.
class OnCallEventJob < ApplicationJob
  queue_as :default

  def perform(source:, event:)
    OnCallSyncService.new(source.workspace).apply(source, Integrations::Paging::Event.from_job(event))
  end
end

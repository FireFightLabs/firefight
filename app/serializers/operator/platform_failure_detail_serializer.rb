module Operator
  # A failed platform call as its page heads it: where it failed, why, and when the same failure was first kept.
  class PlatformFailureDetailSerializer < BaseSerializer
    Detail = Data.define(:failure, :reason, :first_at)

    object_as :detail

    type :string
    def platform = detail.failure.platform.titleize

    type :string
    def operation = detail.failure.operation

    type :string
    def workspace = detail.failure.workspace.name

    type :string
    def workspace_id = detail.failure.workspace_id

    type :string, optional: true
    def channel = detail.failure.channel_id

    type :string
    def reason = detail.reason.code

    type "string[]"
    def notes = detail.reason.notes

    type :string
    def first_at = detail.first_at.utc.iso8601
  end
end

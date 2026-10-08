# Firefight's outbound webhook tools were renamed so they are never taken for a provider's webhooks, and a saved runbook
# step names its tool, so the steps that named the old ones follow.
class RenameOutboundWebhookRunbookTools < ActiveRecord::Migration[8.1]
  RENAMED = { "upsert_webhook" => "upsert_outbound_webhook", "delete_webhook" => "delete_outbound_webhook", "test_webhook" => "test_outbound_webhook" }.freeze

  def up
    RENAMED.each { |old, new| execute "UPDATE runbook_steps SET tool = #{quote(new)} WHERE tool = #{quote(old)}" }
  end

  def down
    RENAMED.each { |old, new| execute "UPDATE runbook_steps SET tool = #{quote(old)} WHERE tool = #{quote(new)}" }
  end

  private

  def quote(value) = connection.quote(value)
end

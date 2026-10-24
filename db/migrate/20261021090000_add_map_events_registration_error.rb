# A connection whose provider's change log is read and that is also sent changes keeps why its registration failed apart
# from why the log could not be read, so one failing never says the other is off. The confirmations a person reads before
# turning live updates on were reworded, and a connection already asked keeps the words it was asked with, so those are
# moved to the new words.
class AddMapEventsRegistrationError < ActiveRecord::Migration[8.1]
  REWORDED = {
    "Firefight subscribes this connection to each subscription's resource changes through Event Grid, so a change reaches the map " \
    "within about a minute. Azure makes an Event Grid system topic for the subscription to send them. The service principal needs the " \
    "EventGrid EventSubscription Contributor role on each subscription, and Microsoft.EventGrid registered as a resource provider there. " \
    "The activity log is still read every 5 minutes." =>
      "To set this up, the app registration Firefight signs in with needs the EventGrid EventSubscription Contributor role on each Azure " \
      "subscription it reads, and each subscription needs Microsoft.EventGrid registered under Resource providers in the Azure portal. " \
      "Firefight then adds an Event Grid webhook named firefightliveupdates to each subscription, and turning instant updates off removes it.",
    "Convex lets a deployment send to one webhook log stream, so Firefight's would be this deployment's only one and the team could " \
    "not add its own. Log streams need Convex's Pro plan." =>
      "Convex allows one webhook log stream per deployment, so your team could not add its own while this is on. Log streams need " \
      "Convex's Pro plan."
  }.freeze

  class IntegrationEnvironment < ActiveRecord::Base
    self.table_name = "integration_environments"
  end

  # Azure is the one provider whose change log is read and that is registered with as well. Why its registration failed
  # was kept with the activity log's own error, which made the log read as off, and often held Azure's raw answer, which a
  # person is no longer shown. Its error is cleared rather than moved, Instant updates read as off until someone turns
  # them on again, and a reason the log itself cannot be read is written again by the next read, within five minutes.
  BOTH_WAYS = "azure".freeze

  def up
    add_column :integration_environments, :map_events_registration_error, :string
    reword(REWORDED)
    clear_registration_failures
  end

  def down
    reword(REWORDED.invert)
    remove_column :integration_environments, :map_events_registration_error
  end

  private

  def clear_registration_failures
    IntegrationEnvironment.where("integration_id IN (SELECT id FROM integrations WHERE provider = ?)", BOTH_WAYS).where.not(map_events_error: nil)
                          .update_all(map_events_error: nil)
  end

  def reword(words)
    words.each { |from, to| IntegrationEnvironment.where(map_events_confirmation: from).update_all(map_events_confirmation: to) }
  end
end

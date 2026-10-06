class AddLiveUpdatesConsent < ActiveRecord::Migration[8.1]
  def change
    change_table :integration_environments, bulk: true do |t|
      # What registering the provider's webhook costs the account, such as its only webhook slot, when a person decides.
      t.string :map_events_confirmation
      # When a person turned live updates off, after which Firefight does not register again on its own.
      t.datetime :map_events_turned_off_at
      # When the provider last refused a registration for its plan or a limit, so it is tried again a day later.
      t.datetime :map_events_refused_at
    end
  end
end

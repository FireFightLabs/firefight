module Entitlements
  # What a hosted build tells setup about the plan it sells a workspace. Every sentence is finished by the backend,
  # since only it knows the price, the trial and the dates.
  #
  # active: a trial or a plan is running, so setup can move on. price ("$99") and price_note ("Early adopter price")
  # head the offer, included lists what comes with it, and trial_days is the free trial a start gives, nil when a start
  # charges at once. terms says when the card is charged, under the button. summary says where the plan stands once it is
  # active. start_path is the POST that opens checkout, and start_blocked_reason says why it cannot open yet.
  Plan = Data.define(:active, :price, :price_note, :included, :trial_days, :terms, :summary, :start_path, :start_blocked_reason) do
    def active? = active
  end
end

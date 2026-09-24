# Lets a chat's box go once nobody has asked anything that reads code for a while.
class CodeBoxIdleJob < ApplicationJob
  queue_as :background

  def perform(key)
    Integrations::CodeReading.close_idle(key)
  end
end

# Base interface for platform-specific interaction parsers.
# Each platform implements `.parse(payload)` to turn its raw interaction
# payload (button click, view submission, shortcut) into a platform-agnostic
# `Interaction` PORO.
#
#   class Slack::InteractionParser < InteractionParser
#     def self.parse(payload)
#       # ...
#     end
#   end
class InteractionParser
  def self.parse(_payload)
    raise NotImplementedError, "#{name} must implement .parse"
  end
end

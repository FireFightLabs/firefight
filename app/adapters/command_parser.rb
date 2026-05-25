# Base interface for platform-specific command parsers.
# Each platform implements `.parse(payload)` to turn its raw slash-command
# payload into a platform-agnostic `Command` PORO.
#
#   class Slack::CommandParser < CommandParser
#     def self.parse(payload)
#       # ...
#     end
#   end
class CommandParser
  def self.parse(_payload)
    raise NotImplementedError, "#{name} must implement .parse"
  end
end

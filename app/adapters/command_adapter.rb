# Base interface for platform-specific command adapters
# Defines the contract that all platform adapters must implement
#
# Usage:
#   class Slack::CommandAdapter < CommandAdapter
#     def self.parse(payload)
#       # Implementation
#     end
#   end
class CommandAdapter
  # Parse platform-specific payload into a platform-agnostic Command object
  #
  # @param payload [Hash] Platform-specific command payload
  # @return [Command] Platform-agnostic command object
  # @raise [NotImplementedError] Must be implemented by subclasses
  def self.parse(payload)
    raise NotImplementedError, "#{self.class.name} must implement #parse"
  end
end

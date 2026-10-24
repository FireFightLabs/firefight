module Integrations
  module MitigationReaders
    # qstash_manage_schedule creates, reads, deletes, pauses or resumes a QStash schedule (upstash.com/docs/agent-resources/mcp),
    # so a call is a mitigation when it pauses one, which stops its messages until it is resumed. Upstash does not publish
    # the tool's parameters, so the action is read from whichever argument the connected tool reports offering pause.
    module Upstash
      TOOL = "qstash_manage_schedule".freeze
      ACTIONS = %w[action operation].freeze
      PAUSE = "pause".freeze
      RESUME = "resume".freeze

      def self.mitigation?(tool, arguments)
        name = action_argument(tool)
        name.present? && arguments[name].to_s.strip.casecmp?(PAUSE)
      end

      # A paused schedule is undone by resuming it, when the connected tool offers resume. Asked only of a call already
      # taken for a mitigation.
      def self.undo_words(tool, arguments)
        Mitigations::RESUMES if undo_arguments(tool, arguments)
      end

      # The same call with resume in place of pause, so the schedule it named is resumed.
      def self.undo_arguments(tool, arguments)
        name = action_argument(tool)
        return unless name && mitigation?(tool, arguments) && actions(tool, name).include?(RESUME)

        arguments.merge(name => RESUME)
      end

      def self.action_argument(tool)
        return unless tool.name == TOOL

        ACTIONS.find { |name| actions(tool, name).include?(PAUSE) }
      end

      def self.actions(tool, name) = Array(tool.params_schema.to_h.fetch("properties", {}).dig(name, "enum")).map(&:to_s)
      private_class_method :actions
      private_class_method :action_argument
    end
  end
end

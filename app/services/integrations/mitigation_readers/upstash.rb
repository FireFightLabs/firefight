module Integrations
  module MitigationReaders
    # qstash_manage_schedule creates, reads, deletes, pauses or resumes a QStash schedule (upstash.com/docs/agent-resources/mcp),
    # so a call is a mitigation when it pauses one, which stops its messages until it is resumed. Upstash does not publish
    # the tool's parameters, so the action is read from whichever argument the connected tool reports offering pause.
    module Upstash
      TOOL = "qstash_manage_schedule".freeze
      ACTIONS = %w[action operation].freeze
      PAUSE = "pause".freeze

      def self.mitigation?(tool, arguments)
        name = action_argument(tool)
        name.present? && arguments[name].to_s.strip.casecmp?(PAUSE)
      end

      # A paused schedule is undone by resuming it. Asked only of a call already taken for a mitigation.
      def self.undo_words(tool, arguments)
        Mitigations::STARTS_AGAIN if mitigation?(tool, arguments)
      end

      def self.action_argument(tool)
        return unless tool.name == TOOL

        properties = tool.params_schema.to_h.fetch("properties", {})
        ACTIONS.find { |name| Array(properties.dig(name, "enum")).map(&:to_s).include?(PAUSE) }
      end
      private_class_method :action_argument
    end
  end
end

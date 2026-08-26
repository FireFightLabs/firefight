module Slack
  module Messages
    module Invite
      # Everything this says is about people, so it names them rather than
      # reporting counts alone.
      # Nobody to invite, said in the vocabulary of the command they ran.
      def self.unresolved(targets)
        unless targets[:had_target_tokens]
          return "No users specified. Try `/ff invite @alice @bob` or `/ff invite` to pick responders from the modal."
        end

        handles = targets[:unresolved_handles].map { |handle| "@#{handle}" }.join(", ")
        "Couldn't resolve #{handles}. Try `/ff invite` to pick responders from the modal."
      end

      def self.summary(result)
        parts = []

        invited = result.invited.size
        parts << "Invited #{invited} responder#{'s' unless invited == 1}." if invited.positive?

        already = result.already_in_channel
        if already.any?
          parts << "#{already.map { |person| mention(person) }.join(', ')} #{already.one? ? 'is' : 'are'} already in this channel."
        end

        parts << "#{result.failed.size} failed." if result.failed.any?
        parts << "No responders were invited." if parts.empty?

        parts.join(" ")
      end

      # The slash command resolves handles to platform ids and never looks up a
      # member, so a round started there holds ids where one started from the
      # dashboard holds people. This is the only place that difference reaches.
      def self.mention(person)
        person.is_a?(String) ? "<@#{person}>" : Mrkdwn.mention(person)
      end
      private_class_method :mention
    end
  end
end

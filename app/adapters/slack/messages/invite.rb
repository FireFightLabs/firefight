module Slack
  module Messages
    module Invite
      # What the person who ran the invite gets back. Everything it says is
      # about people, so it names them rather than reporting counts alone.
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

        invited = result.invited_user_ids.size
        parts << "Invited #{invited} responder#{'s' unless invited == 1}." if invited.positive?

        already = result.already_in_channel_user_ids
        if already.any?
          parts << "#{already.map { |id| "<@#{id}>" }.join(', ')} #{already.one? ? 'is' : 'are'} already in this channel."
        end

        parts << "#{result.failed_invites.size} failed." if result.failed_invites.any?
        parts << "No responders were invited." if parts.empty?

        parts.join(" ")
      end
    end
  end
end

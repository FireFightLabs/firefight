module Operator
  # What people wrote in the chat platform, as the console shows it: names, channels and emoji as the platform shows
  # them. The controller hands in the app's own reading (PlatformText#platform_texts_in), since the console never calls
  # a platform itself. A trace keeps what the model read beside it, for the operator to compare.
  class Readable
    # Reads every text as it is stored, for a place no platform reading reaches, such as a count.
    def self.none = new(nil)

    # shown takes a workspace and texts in its platform's markup, and answers each mapped to how it reads.
    def initialize(shown)
      @shown = shown
      @read = Hash.new { |hash, workspace_id| hash[workspace_id] = {} }
    end

    def text(workspace, raw)
      return raw if raw.blank? || @shown.nil?

      known = @read[workspace.id]
      known.merge!(@shown.call(workspace, [ raw ])) unless known.key?(raw)
      known.fetch(raw, raw)
    end

    def question(run)
      run.question_in_platform_markup? ? text(run.workspace, run.question) : run.question
    end

    # Named by its incident or check, or by its question as people read it.
    def run_label(run)
      run.incident || run.check || !run.question_in_platform_markup? ? run.label : question(run).to_s
    end

    def chat_title(conversation)
      said = conversation.title_question
      said ? text(conversation.workspace, said).truncate(Conversation::TITLE_LIMIT) : conversation.display_title
    end

    # A person's message as people read it, or the message as saved when it was not written in the platform.
    def said(conversation, message)
      raw = conversation.said_in_platform(message)
      raw ? text(conversation.workspace, raw) : message.content.to_s
    end
  end
end

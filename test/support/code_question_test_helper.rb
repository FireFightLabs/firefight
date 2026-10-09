# A coding agent's question as the agent asks it now: the question, its options with what each leads to, and the one it
# recommends with why.
module CodeQuestionTestHelper
  TAG_OR_COMMIT = [
    { "label" => "Send the tag", "consequence" => "Northflank names the run after the release, such as v1.4.0." },
    { "label" => "Send the commit", "consequence" => "Northflank names the run after the commit, such as 3f2a9c1." }
  ].freeze
  TAG_REASON = "The release workflow already names its runs after the tag.".freeze

  def ask_question!(session, text, options: TAG_OR_COMMIT, recommended: TAG_OR_COMMIT.first["label"], reason: TAG_REASON)
    CodeAgentQuestion.ask!(session, text, options: options, recommended: recommended, reason: reason)
  end
end

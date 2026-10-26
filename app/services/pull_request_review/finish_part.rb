# How the reviewer says it has reviewed every file of the part in front of it, which ends that part.
class PullRequestReview::FinishPart < RubyLLM::Tool
  NAME = "finish_part".freeze

  description "Say you have reviewed every file of this part. Call it once, last, after every finding you could show is reported."
  parameter :reviewed, description: "One plain sentence on what this part changes and what you checked"

  attr_reader :said

  def name = NAME

  def finished? = !@said.nil?

  # Ready for the next part.
  def reset! = @said = nil

  def execute(reviewed:)
    @said = reviewed.to_s.strip
    "Done with this part."
  end
end

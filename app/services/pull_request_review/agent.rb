# What the shared tools ask of whoever they run for, for one chat of a pull request review: the review's own, or one
# check's. A review reads as Halon, the investigator agent, with its own grants, since the person who asked on the code
# host is not someone Firefight knows. It only reads, never waits for a person and keeps nothing to run later. Every
# call goes through the gateway and is in the activity log under the review, and every part and check of one review
# reads in the same sandbox.
class PullRequestReview::Agent
  # Firefight's own tools that help review code: what happened before, what fired, where things run and what depends
  # on them, and what the team wrote down. Permissions, access and setup are about the workspace, never the change.
  FIREFIGHT_GROUPS = [
    Chat::Tools::Groups::INCIDENT_HISTORY, Chat::Tools::Groups::ALERTS, Chat::Tools::Groups::CATALOG, Chat::Tools::Groups::MAP,
    Chat::Tools::Groups::RESOURCES, Chat::Tools::Groups::FOLLOW_UPS, Chat::Tools::Groups::POSTMORTEMS
  ].freeze

  attr_reader :review, :chat

  def initialize(review, chat:)
    @review = review
    @chat = chat
  end

  # What the agent holds from the start and what its provider's tool search finds (Chat::Tools.presented), less
  # Firefight's own tools outside FIREFIGHT_GROUPS.
  def tools(choice)
    presented = Chat::Tools.presented(self, choice)
    kept = ->(tool) { kept?(tool.name.to_s) }
    loaded = presented.loaded.select(&kept)
    [ [ Chat::Tools::Open.new(self, offer: Chat::Tools.offer_to(chat), presented: presented), Chat::Tools::ReadResult.new(self), *loaded ],
      presented.deferred.select(&kept) ]
  end

  def acting_principal = SystemAgent.investigator
  def workspace = review.workspace
  def chat_owner = chat&.owner || review
  def incident = nil
  def reads_only? = true
  def changes_memory? = false
  def uses_skills? = false
  def code_box_key = review.code_box_key
  def progress_listener(_tool_call_id) = nil
  def confirms?(*, **) = false
  def hold!(*, **) = false
  def mark_step_failed!(_position, _kind) = nil
  def pack_refused!(_action_key, _tool_call_id) = nil

  def refusal(action_key)
    "Not allowed: Halon has no grant for #{action_key} in this workspace. Review with what you can read, and say in why what you could not check."
  end

  def tool_call(action_key:, params: {}, scope: {}, approval_id: nil, holdable: true, **, &block)
    value = Chat::ToolCall.run!(
      workspace: workspace, principal: acting_principal, action_key: action_key, params: params, scope: scope,
      context: { source: AbilityGateway::SOURCE_PULL_REQUEST_REVIEW, triggered_by_label: label, approval_id: approval_id }.compact,
      holdable: holdable, &block
    )
    Chat::ToolCall::Outcome.new(value: value)
  end

  private

  # How the activity log names what the review was for.
  def label = "Review of PR ##{review.number} in #{review.repository}"

  def kept?(name) = !self.class.firefight_names.include?(name) || FIREFIGHT_GROUPS.include?(Chat::Tools::Groups.of_firefight_tool(name))

  def self.firefight_names = @firefight_names ||= FirefightTools.all.to_set { |tool_class| tool_class.name_value.to_s }
end

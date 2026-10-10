# Proposes an edit to a handbook page a fresh reading contradicted, or a new page Halon drafted. A person accepts, edits
# or dismisses it, so the handbook never changes on Halon's word alone.
class Chat::Tools::ProposeHandbookEdit < RubyLLM::Tool
  def self.tool_name = "propose_handbook_edit"

  def initialize(agent_run)
    super()
    @agent_run = agent_run
  end

  def name = self.class.tool_name

  def description
    "Propose an edit to a page of this workspace's handbook when a result you read now contradicts it, such as releases " \
      "running through a different tool than the page says, or propose a new page when asked to draft the handbook or " \
      "when something the team relies on is written nowhere. Nothing changes until a person accepts it. Write the whole " \
      "page as it should read, keeping everything the result did not contradict, and say what showed it."
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "page" => { "type" => "string", "description" => "The title of the page to change, as the handbook names it. Leave it out to propose a new page" },
        "title" => { "type" => "string", "description" => "The new page's title, at most #{Chat::HandbookPage::TITLE_LIMIT} characters, only for a new page" },
        "text" => { "type" => "string", "description" => "The whole page as it should read, in Markdown" },
        "evidence" => { "type" => "string", "description" => "What showed it and where, in one or two sentences, such as \"The last five releases ran through the deploy workflow, not the release pipeline.\"" }
      },
      "required" => [ "text", "evidence" ]
    }
  end

  # The arguments match the schema above, not an execute signature, so skip the base check.
  def call(tool_call: nil, **arguments)
    asked = arguments.stringify_keys
    text = asked["text"].to_s.strip
    page = find_page(asked["page"])
    return refused(tool_call, "There is no handbook page called #{asked['page']}. Name one the handbook has, or leave page out and give a title for a new page.") if asked["page"].present? && page.nil?
    return refused(tool_call, "Give the new page a title.") if page.nil? && asked["title"].to_s.strip.empty?

    title = asked["title"].to_s.squish unless page
    waiting = Chat::HandbookProposal.waiting_from(@agent_run.chat_owner, page: page, title: title)
    return refused(tool_call, "You already proposed this here, and it still waits on a person.") if waiting
    return refused(tool_call, "The handbook already says that.") if page && page.text.strip == text

    proposal = HandbookProposalService.new(@agent_run.workspace).propose!(@agent_run.chat_owner, page: page, title: title, text: text,
                                                                                                 evidence: asked["evidence"].to_s.strip)
    "Proposed. #{where_asked(proposal)} Until someone accepts it, the handbook stays as it is."
  rescue ActiveRecord::RecordInvalid => error
    refused(tool_call, "#{error.record.errors.full_messages.to_sentence} Nothing was proposed.")
  end

  private

  def find_page(title)
    wanted = title.to_s.squish
    return nil if wanted.empty?

    Chat::HandbookPage.where(workspace: @agent_run.workspace).where("lower(title) = ?", wanted.downcase).first
  end

  def where_asked(proposal)
    return "A card in this chat asks the person to accept, edit or dismiss it." if proposal.conversation&.personal?
    return "The incident's channel is asked to accept, edit or dismiss it, and so is the Handbook page." if proposal.incident&.channel_id.present?

    "It waits on the Handbook page for a person to accept, edit or dismiss it."
  end

  def refused(tool_call, words)
    Chat::Tools.mark_failed(@agent_run, tool_call&.id)
    words
  end
end

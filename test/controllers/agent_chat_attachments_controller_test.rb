require "test_helper"

class AgentChatAttachmentsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "a file is uploaded as it is added, and comes back as a chip" do
    post agent_chat_attachments_url, params: { file: fixture_file_upload("halon_graph.png", "image/png") }

    assert_response :created
    file = @workspace.chat_attachments.sole
    assert_equal({ "id" => file.id, "name" => "halon_graph.png", "size" => file.byte_size.to_fs(:human_size, precision: 2),
                   "kind" => Chat::Attachment::KIND_IMAGE, "url" => agent_chat_attachment_path(file), "unreadReason" => nil },
                 response.parsed_body)
    assert_equal @member, file.uploaded_by
    assert_not file.sent?
  end

  test "a file Halon does not read is refused with the sentence saying what is accepted" do
    post agent_chat_attachments_url, params: { file: Rack::Test::UploadedFile.new(StringIO.new("PK\u0003\u0004\u0000\u0000".b), "application/zip", true, original_filename: "dump.zip") }

    assert_response :unprocessable_content
    assert_equal "dump.zip is not a file Halon reads. #{Chat::Attachment::ACCEPTED}", response.parsed_body["error"]
    assert_empty @workspace.chat_attachments
  end

  test "a file over the largest limit is refused before it is read" do
    Chat::Attachment.expects(:take!).never
    upload = Rack::Test::UploadedFile.new(StringIO.new("a" * (Chat::Attachment::LARGEST + 1)), "text/plain", original_filename: "huge.log")

    post agent_chat_attachments_url, params: { file: upload }

    assert_response :unprocessable_content
    assert_match "huge.log is 10 MB", response.parsed_body["error"]
  end

  test "an upload needs the same permission as asking" do
    AbilityGateway.stubs(:authorize!).raises(AbilityGateway::Denied.new(Ability::Action.system_key(Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE)))

    post agent_chat_attachments_url, params: { file: fixture_file_upload("halon_graph.png", "image/png") }

    assert_redirected_to dashboard_path
    assert_empty @workspace.chat_attachments
  end

  test "the uploads go with the first question, which may be files alone" do
    file = upload("deploy.log", "boom")

    assert_enqueued_with(job: ConversationReplyJob) do
      post agent_chats_url, params: { question: "", attachment_ids: [ file.id ] }
    end

    conversation = @workspace.conversations.sole
    assert_redirected_to agent_chat_path(conversation)
    assert_equal "deploy.log", conversation.title
    assert_equal conversation.chat, file.reload.chat
  end

  test "an open chat shows each message's files and what the composer takes" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    file = upload("deploy.log", "boom")
    post agent_chat_ask_url(conversation), params: { question: "why", attachment_ids: [ file.id ] }

    get agent_chat_url(conversation), headers: inertia_headers

    assert_equal [ "deploy.log" ], inertia_props["messages"].sole["attachments"].pluck("name")
    assert_equal Chat::Attachment::MAX_PER_MESSAGE, inertia_props.dig("attachmentRules", "maxFiles")
    assert_nil inertia_props.dig("attachmentRules", "imagesUnread")
  end

  test "the page says before sending when the chat's model is not known to read images" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    conversation.ask!("hello")
    conversation.chat.update!(model: "gpt-3.5-turbo")

    get agent_chat_url(conversation), headers: inertia_headers

    assert_equal Chat::Attachment::IMAGES_UNREAD, inertia_props.dig("attachmentRules", "imagesUnread")
  end

  test "someone else's upload cannot be sent, and the question is not asked" do
    theirs = Chat::Attachment.take!(workspace: @workspace, uploaded_by: workspace_memberships(:bob_workspace_one), filename: "b.log", bytes: "b")

    assert_no_enqueued_jobs(only: ConversationReplyJob) do
      post agent_chats_url, params: { question: "look", attachment_ids: [ theirs.id ] }
    end

    assert_equal Chat::Attachment::NOT_FOUND, flash[:alert]
    assert_not theirs.reload.sent?
  end

  test "a sent file is read back by whoever reads the chat, and an image is shown inline and never run" do
    file = upload("halon_graph.png", file_fixture("halon_graph.png").binread)
    post agent_chats_url, params: { question: "look", attachment_ids: [ file.id ] }

    get agent_chat_attachment_url(file)

    assert_response :success
    assert_equal file_fixture("halon_graph.png").binread, response.body
    assert_equal "image/png", response.media_type
    assert_match "inline", response.headers["Content-Disposition"]
    assert_match "sandbox", response.headers["Content-Security-Policy"]
  end

  test "a text file is downloaded, never shown as a page" do
    file = upload("page.html", "<script>alert(1)</script>")

    get agent_chat_attachment_url(file)

    assert_equal "text/plain", response.media_type
    assert_match "attachment", response.headers["Content-Disposition"]
  end

  test "nobody else reads a file, sent or not" do
    file = upload("secret.log", "s")
    sign_in(users(:bob), @workspace)

    get agent_chat_attachment_url(file)
    assert_response :not_found

    delete agent_chat_attachment_url(file)
    assert Chat::Attachment.exists?(file.id)
  end

  test "taking a file off before sending deletes the upload, and a sent one cannot be taken off" do
    file = upload("a.log", "a")

    delete agent_chat_attachment_url(file)

    assert_response :no_content
    assert_not Chat::Attachment.exists?(file.id)

    sent = upload("b.log", "b")
    post agent_chats_url, params: { question: "look", attachment_ids: [ sent.id ] }
    delete agent_chat_attachment_url(sent)
    assert_response :not_found
  end

  private

  def upload(name, bytes)
    Chat::Attachment.take!(workspace: @workspace, uploaded_by: @member, filename: name, bytes: bytes)
  end
end

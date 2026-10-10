require "test_helper"

# A repair Halon proposes through PlanetScale's server: the rows it touches are counted and shown before Alice is asked,
# counted again and copied right before it runs, and the check Halon gave is counted after.
class Chat::DataRepairsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  WRITE = "UPDATE orders SET currency = 'USD' WHERE currency IS NULL".freeze
  CHECK = "SELECT id FROM orders WHERE currency IS NULL".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @turn = Conversation::Turn.new(@conversation, asker: @alice)
    @chat = @conversation.chat_record
    planetscale = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "planetscale", name: "PlanetScale", slug: "planetscale",
                                                  settings: { "server_url" => "https://mcp.pscale.dev/mcp/planetscale" })
    planetscale.integration_environments.create!
    schema = { "type" => "object", "properties" => { "organization" => {}, "database" => {}, "branch" => {}, "query" => {} } }
    @write = planetscale.tools.create!(name: "execute_write_query", description: "Write", enabled: true, read_only: false,
                                       params_schema: schema.deep_merge("properties" => { "confirm_destructive" => {} }))
    @read = planetscale.tools.create!(name: "execute_read_query", description: "Read", enabled: true, read_only: true, params_schema: schema)
    @database = FakeDatabase.new
    @reads = @database.reads
    Integration.any_instance.stubs(:executor).returns(@database)
  end

  teardown do
    assert_empty @database.writes, "nothing was written" if @expect_no_write
  end

  test "a tool whose provider declares it a data write has that effect on its action, and its read does not" do
    assert @write.reload.ability_action.effect?(Ability::Action::EFFECT_DATA_WRITE)
    assert_empty @read.reload.ability_action.effects
  end

  test "a write is counted and a few of its rows read before the person is asked, and never offered for the rest of the chat" do
    answer_reads(touched: 42, wrong: 42)

    assert_nil tool.approval_resolver.call(write_call), "a counted write is put to the person"
    repair = Chat::DataRepair.for_call(@chat, "call_1")

    assert_equal 42, repair.rows_counted
    assert_equal 42, repair.wrong_before
    assert_match "id | currency", repair.sample
    assert_equal [ "Rows it changes", "42 rows of orders" ], repair.confirmation_rows.first
    assert_equal({ "organization" => "acme", "database" => "shop", "branch" => "main", "query" => "SELECT * FROM (SELECT * FROM orders WHERE currency IS NULL) AS halon_touched LIMIT 5" },
                 @reads.find { |asked| asked["query"].include?("LIMIT 5") }, "the read takes the write's own arguments, less what only a write takes")
    assert @reads.all? { |asked| asked.exclude?("confirm_destructive") }

    call = pause!
    confirmation = Chat::Tools.confirmation(call)
    assert_not confirmation.for_chat
    assert_includes confirmation.safeguards, [ "Rows it changes", "42 rows of orders" ]
    assert Chat::DataRepairs.asks_each?(@chat, "call_1")
  end

  test "each read is in the activity log as the person, through the read tool, and never waits for an approval rule" do
    answer_reads(touched: 3, wrong: 3)
    Ability::Approval.expects(:create!).never

    tool.approval_resolver.call(write_call)

    ledgered = Ability::Invocation.where(workspace: @workspace, action_key: @read.action_key)
    assert_equal 3, ledgered.count
    assert ledgered.all? { |row| row.principal_id == @alice.id && row.source == AbilityGateway::SOURCE_CONVERSATION }
  end

  test "a write without a check is refused before anyone is asked, and never sent" do
    expect_no_write

    assert_equal true, tool.approval_resolver.call(write_call(check: nil))
    refused = tool.call(tool_call: write_call(check: nil), **write_arguments(check: nil).symbolize_keys)

    assert_match "Not run. Give check: one SELECT returning the rows that are still wrong", refused
  end

  test "a write Firefight cannot count first is refused with how to write it instead" do
    expect_no_write

    assert_equal true, tool.approval_resolver.call(write_call(query: "UPDATE a SET x = b.x FROM b WHERE a.id = b.id"))
    assert_match "An UPDATE with FROM", Chat::DataRepair.for_call(@chat, "call_1").refusal
  end

  test "a write touching more rows than Firefight copies before one write is refused, asking for batches" do
    answer_reads(touched: 5_000, wrong: 5_000)
    expect_no_write

    assert_equal true, tool.approval_resolver.call(write_call)
    assert_match "It touches 5000 rows, more than the 1000", Chat::DataRepair.for_call(@chat, "call_1").refusal
  end

  test "once confirmed, the rows are counted again and copied, the write runs, and the check is counted after" do
    answer_reads(touched: 42, wrong: 42)
    tool.approval_resolver.call(write_call)
    pause!.update_columns(approval: Chat::APPROVAL_APPROVED)
    answer_reads(touched: 42, wrong: 0, write: "Query OK, 42 rows affected")

    said = tool.call(tool_call: write_call, **write_arguments.symbolize_keys)
    repair = Chat::DataRepair.for_call(@chat, "call_1")

    assert_match "Query OK, 42 rows affected", said
    assert_match "Firefight counted 42 rows of orders before this ran.", said
    assert_match "A copy of the rows it touched is kept until", said
    assert_match "Check: 42 rows were wrong before, none are now.", said
    assert_equal Chat::DataRepair::STATUS_RAN, repair.status
    assert_equal 42, repair.rows_copied
    assert_match "id | currency", repair.rows_copy
    assert_not_includes Chat::DataRepair.connection.select_value("SELECT rows_copy FROM chat_data_repairs WHERE id = '#{repair.id}'"), "id | currency"
    assert_equal 1, @reads.count { |asked| asked["query"].include?("ORDER BY 1 LIMIT 100 OFFSET 0") }, "42 rows are one page"
  end

  test "a write whose rows changed since the person confirmed is not run" do
    answer_reads(touched: 42, wrong: 42)
    tool.approval_resolver.call(write_call)
    pause!.update_columns(approval: Chat::APPROVAL_APPROVED)
    answer_reads(touched: 57, wrong: 57)
    expect_no_write

    said = tool.call(tool_call: write_call, **write_arguments.symbolize_keys)

    assert_match "The person confirmed this for 42 rows of orders, but it now touches 57", said
  end

  test "a read through a tool that also writes is asked about as before, and runs unasked once allowed for the chat" do
    supabase = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "supabase", name: "Supabase", slug: "supabase",
                                               settings: { "server_url" => "https://mcp.supabase.com/mcp" })
    supabase.integration_environments.create!
    sql = supabase.tools.create!(name: "execute_sql", description: "SQL", enabled: true, read_only: false,
                                 params_schema: { "type" => "object", "properties" => { "query" => {} } })
    entry = Chat::Tools::Connection.new(@turn, sql)
    reading = RubyLLM::ToolCall.new(id: "call_2", name: entry.name, arguments: { "query" => "SELECT 1", "intent" => "Look" })

    assert entry.requires_approval?
    assert_nil entry.approval_resolver.call(reading)

    @chat.allow_tool!(entry.name)
    @conversation.chat.reload
    assert_equal true, Chat::Tools::Connection.new(@turn, sql).approval_resolver.call(reading)
    writing = RubyLLM::ToolCall.new(id: "call_3", name: entry.name, arguments: { "query" => WRITE, "check" => CHECK, "intent" => "Fix" })
    answer_reads(touched: 2, wrong: 2)
    assert_nil Chat::Tools::Connection.new(@turn, sql).approval_resolver.call(writing), "a write is asked about whatever was allowed"
  end

  test "each write in a transaction is counted and copied, and the transaction runs once after it is confirmed" do
    transaction = neon_transaction
    statements = [ WRITE, "DELETE FROM carts WHERE abandoned" ]
    answer_reads(touched: 3, wrong: 3)
    tool = Chat::Tools::Connection.new(@turn, transaction)
    call = RubyLLM::ToolCall.new(id: "call_4", name: tool.name, arguments: { "sqlStatements" => statements, "check" => CHECK, "intent" => "Fix" })

    assert_nil tool.approval_resolver.call(call)
    repair = Chat::DataRepair.for_call(@chat, "call_4")
    assert_equal 6, repair.rows_counted
    assert_equal "6 rows of orders and carts", repair.rows_words
    assert @reads.all? { |asked| asked.key?("sql") && asked.exclude?("sqlStatements") }, "each read goes through run_sql with its own sql"

    message = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    message.ruby_llm_tool_calls.create!(tool_call_id: "call_4", name: tool.name, arguments: call.arguments, approval: Chat::APPROVAL_APPROVED)
    answer_reads(touched: 3, wrong: 0, write: "COMMIT")
    said = Chat::Tools::Connection.new(@turn, transaction).call(tool_call: call, **call.arguments.symbolize_keys)

    assert_match "Firefight counted 6 rows of orders and carts before this ran.", said
    assert_equal [ statements ], @database.writes.map { |asked| asked["sqlStatements"] }
    assert_equal 6, repair.reload.rows_copied
  end

  test "a transaction with one statement Firefight cannot count first is refused whole, naming it" do
    transaction = neon_transaction
    expect_no_write
    tool = Chat::Tools::Connection.new(@turn, transaction)
    call = RubyLLM::ToolCall.new(id: "call_5", name: tool.name,
                                 arguments: { "sqlStatements" => [ WRITE, "UPDATE a SET x = b.x FROM b WHERE a.id = b.id" ], "check" => CHECK, "intent" => "Fix" })

    assert_equal true, tool.approval_resolver.call(call)
    assert_match "Not run. Statement 2: An UPDATE with FROM", Chat::DataRepair.for_call(@chat, "call_5").refusal
    assert_match "Nothing in the transaction was run.", Chat::DataRepair.for_call(@chat, "call_5").refusal
  end

  test "the copy is dropped once kept long enough, leaving the counts" do
    repair = Chat::DataRepair.create!(chat: @chat, workspace: @workspace, tool_call_id: "call_9", tool_name: @write.model_facing_name,
                                      action_key: @write.action_key, statement_kind: Integrations::DataWrites::Statement::KIND_DELETE,
                                      status: Chat::DataRepair::STATUS_RAN, rows_counted: 2, rows_copy: "id\n1\n2", copy_expires_at: 1.minute.ago)

    DataRepairCopyCleanupJob.perform_now

    assert_nil repair.reload.rows_copy
    assert repair.copy_cleared_at
    assert_equal 2, repair.rows_counted
  end

  private

  def tool = Chat::Tools::Connection.new(@turn, @write)

  def neon_transaction
    neon = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "neon", name: "Neon", slug: "neon",
                                           settings: { "server_url" => "https://mcp.neon.tech/mcp" })
    neon.integration_environments.create!
    neon.tools.create!(name: "run_sql", description: "SQL", enabled: true, read_only: false, params_schema: { "type" => "object", "properties" => { "sql" => {} } })
    neon.tools.create!(name: "run_sql_transaction", description: "SQL", enabled: true, read_only: false,
                       params_schema: { "type" => "object", "properties" => { "sqlStatements" => { "type" => "array" } } })
  end

  def write_arguments(query: WRITE, check: CHECK)
    { "organization" => "acme", "database" => "shop", "branch" => "main", "query" => query, "check" => check,
      "confirm_destructive" => true, "intent" => "Set the currency on orders that lost it" }.compact
  end

  def write_call(**given) = RubyLLM::ToolCall.new(id: "call_1", name: @write.model_facing_name, arguments: write_arguments(**given))

  def pause!
    message = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    message.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: @write.model_facing_name, arguments: write_arguments)
    @chat.request_decisions!([ "call_1" ])
    @chat.tool_calls.find_by!(tool_call_id: "call_1")
  end

  # A database behind the provider's server: it answers each read by what it asks, keeps every read and write it was
  # sent, and answers the write itself when given.
  class FakeDatabase
    attr_accessor :touched, :wrong, :write
    attr_reader :reads, :writes

    def initialize
      @reads = []
      @writes = []
    end

    def call(arguments:, **)
      query = (arguments["query"] || arguments["sql"]).to_s
      return answer(@writes.push(arguments) && write) unless query.start_with?("SELECT")

      @reads << arguments
      return answer(%([{"halon_rows": #{wrong}}])) if query.include?("halon_check")
      return answer(%([{"halon_rows": #{touched}}])) if query.start_with?("SELECT count")

      answer("id | currency\n1 | null")
    end

    def answer(said) = { "content" => [ { "type" => "text", "text" => said.to_s } ] }
  end

  def answer_reads(touched:, wrong:, write: nil)
    @database.touched = touched
    @database.wrong = wrong
    @database.write = write
  end

  def expect_no_write
    @expect_no_write = true
  end

  def text(said) = { "content" => [ { "type" => "text", "text" => said.to_s } ] }
end

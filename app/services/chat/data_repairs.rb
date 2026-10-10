# What happens around a statement Halon runs through a tool that writes rows (Integrations::DataWrites). Its rows are
# counted and shown before anyone is asked, counted again and copied right before it runs, and checked after. A tool
# that runs several statements in one transaction is treated the same way, statement by statement, and the whole call
# is refused when any one of them cannot be counted first. Every read goes through the provider's own read tool as the
# person who asked, through the gateway, and never waits for an approval, since it only reads.
module Chat::DataRepairs
  CHECK_ARG = "check".freeze
  CHECK = {
    "type" => "string",
    "description" => "For an UPDATE, DELETE or INSERT: one SELECT returning the rows that are still wrong, which returns none once " \
                     "this worked, such as SELECT id FROM orders WHERE currency IS NULL. Firefight counts it before and after."
  }.freeze
  # Said to the model with the tool's own description.
  DESCRIPTION = "Before a write runs, Firefight counts the rows it touches, keeps a copy of them and runs your check after. " \
                "Each statement is one UPDATE, DELETE or INSERT on one table, at most #{Integrations::DataWrites::COPY_LIMIT} rows " \
                "in all, with check.".freeze

  # A read made to count or copy could not be made, said as why the write did not run.
  class Unreadable < StandardError; end

  # The kinds a call settles as before anyone is asked: it only reads, it changes the schema, it was refused, or it is
  # counted and waits for the person.
  READS = :reads
  SCHEMA = :schema
  REFUSED = :refused
  COUNTED = :counted

  def self.with_check(schema)
    schema = schema.deep_dup
    schema["properties"] = (schema["properties"] || {}).merge(CHECK_ARG => CHECK)
    schema
  end

  # A write whose rows were counted is asked about on its own each time, since each one touches different rows, so
  # allowing it for the rest of the chat is not offered.
  def self.asks_each?(chat, tool_call_id) = Chat::DataRepair.for_call(chat, tool_call_id).present?

  def self.applies?(agent_run, tool) = !agent_run.reads_only? && agent_run.chat.present? && Integrations::DataWrites.write_tool?(tool)

  # Settles a call before it is put to the person, once per call: what it is, and for a write, its rows counted, a few
  # read, and the check counted, kept as a Chat::DataRepair. given is what the agent passed, environment and check
  # included.
  def self.settle(agent_run, tool, tool_call_id, given)
    definition = Integrations::DataWrites.for(tool)
    statements = definition.statements(given).map { |sql| Integrations::DataWrites::Statement.parse(sql) }
    return READS if statements.any? && statements.all?(&:read?)
    return SCHEMA if statements.none? { |statement| statement.refused? || statement.row_write? }

    repair = Chat::DataRepair.for_call(agent_run.chat, tool_call_id)
    return repair.refused? ? REFUSED : COUNTED if repair

    repair = count!(agent_run, tool, definition, tool_call_id, statements, given)
    repair.refused? ? REFUSED : COUNTED
  rescue Integration::UnknownEnvironment
    # The call itself refuses an environment the connection lacks, with the words it always uses.
    REFUSED
  end

  # Right before the write runs: counted again, so what runs is what the person saw, and the rows it touches copied.
  # Returns why it must not run, or nil.
  def self.before_write(agent_run, repair, tool, environment_entry, arguments)
    return repair.refusal if repair.refused?

    definition = Integrations::DataWrites.for(tool)
    writes = repair.parsed_statements.select(&:row_write?)
    counts = writes.map { |statement| rows_of(agent_run, tool, definition, environment_entry, arguments, statement) }
    now = counts.sum
    if now != repair.rows_counted
      return "Not run. The person confirmed this for #{repair.rows_words}, but it now touches #{now}, since the data changed in " \
             "between. Tell them, count again and ask once more if it should still be done."
    end
    copy!(agent_run, repair, tool, definition, environment_entry, arguments, writes.zip(counts).select { |statement, _| statement.touches_existing? }) if repair.touches_existing?
    nil
  rescue Unreadable => error
    "Not run, since Firefight could not count or copy the rows it touches first: #{error.message}"
  end

  # After the write ran: its check counted again. Returns what Halon reads after the provider's answer.
  def self.after_write(agent_run, repair, tool, environment_entry, arguments, ok:)
    unless ok
      repair.finish!(Chat::DataRepair::STATUS_FAILED)
      return nil
    end

    after = (count(agent_run, tool, Integrations::DataWrites.for(tool), environment_entry, arguments, checking(repair)) if repair.check_query.present?)
    repair.finish!(Chat::DataRepair::STATUS_RAN, wrong_after: after, checked_at: Time.current)
    said_after(repair)
  rescue Unreadable => error
    repair.finish!(Chat::DataRepair::STATUS_RAN, check_error: error.message, checked_at: Time.current)
    said_after(repair)
  end

  def self.said_after(repair)
    kept = ("A copy of the rows it touched is kept until #{repair.copy_expires_at.to_date.to_fs(:long)}, which the person can " \
            "download from the chat in Firefight." if repair.copy_kept?)
    check = if repair.check_error.present?
      "The check could not run afterwards: #{repair.check_error} Check it another way and say so."
    elsif repair.wrong_after.nil?
      nil
    elsif repair.wrong_after.zero?
      "Check: #{repair.wrong_before} #{'row'.pluralize(repair.wrong_before)} were wrong before, none are now."
    else
      "Check: #{repair.wrong_after} #{'row'.pluralize(repair.wrong_after)} are still wrong (#{repair.wrong_before} before), so the repair " \
        "did not finish. Tell the person."
    end
    [ "Firefight counted #{repair.rows_words} before this ran.", kept, check ].compact.join(" ")
  end

  # Statements in one transaction are counted as they stand before it runs, each on its own.
  def self.count!(agent_run, tool, definition, tool_call_id, statements, given)
    environment_entry = tool.integration.environment_entry_for(given[Integration::Tool::ENVIRONMENT_ARG])
    arguments = provider_arguments(tool, environment_entry, given)
    writes = statements.select(&:row_write?)
    attributes = {
      chat: agent_run.chat, workspace: agent_run.workspace, asker: agent_run.acting_principal, tool_call_id: tool_call_id.to_s,
      tool_name: tool.model_facing_name, action_key: tool.action_key, environment_id: environment_entry&.id,
      statement: Chat::DataRepair.kept_statements(statements.map(&:sql)), statement_kind: Chat::DataRepair.kind_of(statements),
      table_name: writes.filter_map(&:table_name).uniq.to_sentence.presence, check_query: given[CHECK_ARG].to_s.strip.presence
    }
    refusal = statement_refusal(statements) || check_refusal(writes, attributes[:check_query])
    return Chat::DataRepair.create!(attributes.merge(status: Chat::DataRepair::STATUS_REFUSED, refusal: "Not run. #{refusal}")) if refusal

    counts = writes.map { |statement| rows_of(agent_run, tool, definition, environment_entry, arguments, statement) }
    rows = counts.sum
    if rows > Integrations::DataWrites::COPY_LIMIT
      return Chat::DataRepair.create!(attributes.merge(status: Chat::DataRepair::STATUS_REFUSED, rows_counted: rows, counted_at: Time.current,
                                                       refusal: "Not run. It touches #{rows} rows, more than the #{Integrations::DataWrites::COPY_LIMIT} " \
                                                                "Firefight copies before one write. Do it in batches with a narrower WHERE or a LIMIT."))
    end

    samples = writes.zip(counts).filter_map do |statement, touched|
      next unless statement.touches_existing? && touched.positive?

      read(agent_run, tool, definition, environment_entry, arguments, statement.sample_sql(Chat::DataRepair::SAMPLE_ROWS))
    end
    wrong = (count(agent_run, tool, definition, environment_entry, arguments, Integrations::DataWrites::Statement.counting(attributes[:check_query])) if attributes[:check_query])
    Chat::DataRepair.create!(attributes.merge(rows_counted: rows, counted_at: Time.current, wrong_before: wrong,
                                              sample: samples.any? ? Chat::SecretFree.redacted(samples.join("\n\n")).truncate(Chat::DataRepair::SAMPLE_LIMIT) : nil))
  rescue Unreadable => error
    Chat::DataRepair.create!(attributes.merge(status: Chat::DataRepair::STATUS_REFUSED,
                                              refusal: "Not run, since Firefight could not count the rows it touches first: #{error.message}"))
  end
  private_class_method :count!

  # The first statement that cannot be counted first refuses them all, named by its place when there are several.
  def self.statement_refusal(statements)
    return "There is no statement to run." if statements.empty?

    index = statements.index(&:refused?)
    return unless index

    statements.one? ? statements.first.refusal : "Statement #{index + 1}: #{statements[index].refusal} Nothing in the transaction was run."
  end
  private_class_method :statement_refusal

  # A write that changes rows says how to tell it worked, since a statement that ran is not one that fixed the data.
  def self.check_refusal(writes, check)
    return if writes.empty?
    return "Give check: one SELECT returning the rows that are still wrong, which returns none once this worked." if check.blank?

    "The check must be one SELECT that only reads." unless Integrations::DataWrites::Statement.counting(check)
  end
  private_class_method :check_refusal

  def self.rows_of(agent_run, tool, definition, environment_entry, arguments, statement)
    statement.known_count || count(agent_run, tool, definition, environment_entry, arguments, statement.count_sql)
  end
  private_class_method :rows_of

  def self.checking(repair) = Integrations::DataWrites::Statement.counting(repair.check_query)
  private_class_method :checking

  # Each statement's rows a page at a time, as many pages as it touches rows. counted pairs each statement with its count.
  def self.copy!(agent_run, repair, tool, definition, environment_entry, arguments, counted)
    copied = counted.flat_map do |statement, touched|
      Array.new((touched.to_f / Chat::DataRepair::PAGE_ROWS).ceil) do |page|
        read(agent_run, tool, definition, environment_entry, arguments, statement.page_sql(Chat::DataRepair::PAGE_ROWS, page * Chat::DataRepair::PAGE_ROWS))
      end
    end
    repair.update!(rows_copy: copied.join("\n\n"), rows_copied: repair.rows_counted, copied_at: Time.current,
                   copy_expires_at: Chat::DataRepair::COPY_KEPT_FOR.from_now)
  end
  private_class_method :copy!

  def self.count(agent_run, tool, definition, environment_entry, arguments, sql)
    raise Unreadable, "the statement it would count with could not be written." if sql.blank?

    text = read(agent_run, tool, definition, environment_entry, arguments, sql)
    Integrations::DataWrites.count_in(text) || raise(Unreadable, "the count it asked for did not come back.")
  end
  private_class_method :count

  # One read through the provider's read tool, with the write's own arguments but the statement, as the person asking.
  def self.read(agent_run, tool, definition, environment_entry, arguments, sql)
    reader = read_tool(tool, definition)
    asked = arguments.except(definition.sql, *definition.dropped).merge(definition.read_sql => sql)
    scope = environment_entry ? { "environment" => environment_entry.id } : {}
    agent_run.tool_call(action_key: reader.action_key, params: asked, scope: scope, tool_name: reader.model_facing_name, label: nil, holdable: false) do |authorization|
      integration = reader.integration
      result = integration.executor.call(tool: reader, environment_row: integration.resolve_environment(environment_entry&.id), arguments: asked,
                                         box_key: agent_run.code_box_key, progress: nil, request: nil)
      text = Array(result["content"]).filter_map { |part| part["text"] }.join("\n")
      if result["isError"] == true
        authorization.answer_failed!(text)
        raise Unreadable, text.lines.first.to_s.strip.truncate(300)
      end
      text
    end.value
  rescue AbilityGateway::Denied
    raise Unreadable, "#{agent_run.asker_name} may not use #{reader.model_facing_name}, which Firefight reads the rows with."
  rescue Integrations::Error, Integration::UnknownEnvironment => error
    raise Unreadable, error.message
  end
  private_class_method :read

  def self.read_tool(tool, definition)
    Integrations::DataWrites.read_tool(tool, definition) ||
      raise(Unreadable, "#{tool.integration.display_name}'s #{definition.read_tool} tool is switched off, and Firefight reads the rows with it. An admin can switch it on in Integrations.")
  end
  private_class_method :read_tool

  # What the provider is sent, as the call itself sends it: without Firefight's own arguments, and naming the scope it reaches.
  def self.provider_arguments(tool, environment_entry, given)
    arguments = given.except(Integration::Tool::ENVIRONMENT_ARG, Chat::Tools::INTENT_ARG, CHECK_ARG, Chat::Tools::TrackedIssues::KIND_ARG)
    Integrations::Scopes.resolved(tool.integration.resolve_environment(environment_entry&.id), arguments)
  end
end

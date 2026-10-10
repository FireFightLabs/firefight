# A statement Halon proposed in a chat that changes rows in a database. Before the person is asked, the rows it touches
# are counted and a few kept to show them. Right before it runs they are counted again and copied, and after it runs the
# check Halon gave is counted again. The copy is customer data, so it is encrypted and dropped after COPY_KEPT_FOR.
class Chat::DataRepair < ApplicationRecord
  STATUS_PROPOSED = "proposed"
  STATUS_REFUSED = "refused"
  STATUS_RAN = "ran"
  STATUS_FAILED = "failed"
  STATUSES = [ STATUS_PROPOSED, STATUS_REFUSED, STATUS_RAN, STATUS_FAILED ].freeze

  SAMPLE_ROWS = 5
  # Rows are copied a page at a time, small enough that any provider's read returns a page whole.
  PAGE_ROWS = 100
  COPY_KEPT_FOR = 30.days
  SAMPLE_LIMIT = 4_000

  belongs_to :chat
  belongs_to :workspace
  belongs_to :asker, polymorphic: true, optional: true

  encrypts :statement, :check_query, :sample, :rows_copy

  validates :status, inclusion: { in: STATUSES }
  validates :statement_kind, inclusion: { in: Integrations::DataWrites::Statement::KINDS }

  scope :copy_expired, -> { where.not(rows_copy: nil).where(copy_expires_at: ..Time.current) }

  def self.for_call(chat, tool_call_id) = chat && tool_call_id.present? ? find_by(chat: chat, tool_call_id: tool_call_id.to_s) : nil

  def refused? = status == STATUS_REFUSED

  def copy_kept? = rows_copy.present?

  # The statements are kept as one JSON list, one for a single statement, several for a transaction.
  def self.kept_statements(sqls) = sqls.to_json

  # The kind the card and the confirmation speak of, a change of existing rows when any statement makes one.
  def self.kind_of(statements)
    writes = statements.select(&:row_write?)
    touching = writes.find(&:touches_existing?)
    return touching.kind if touching
    return Integrations::DataWrites::Statement::KIND_INSERT if writes.any?

    Integrations::DataWrites::Statement::KIND_SCHEMA
  end

  def parsed_statements = (statement.blank? ? [] : Array(JSON.parse(statement))).map { |sql| Integrations::DataWrites::Statement.parse(sql) }

  def touches_existing? = Integrations::DataWrites::Statement::TOUCHES_EXISTING.include?(statement_kind)

  # How a person reads what it changes, such as "42 rows of public.orders".
  def rows_words = "#{rows_counted} #{'row'.pluralize(rows_counted)} of #{table_name}"

  # The rows the confirmation shows, beside what the tool was given.
  def confirmation_rows
    return [ [ "Not run", refusal ] ] if refused?

    rows = [ [ statement_kind == Integrations::DataWrites::Statement::KIND_INSERT ? "Rows it adds" : "Rows it changes", rows_words ] ]
    rows << [ "Rows still wrong now", wrong_before.to_s ] unless wrong_before.nil?
    rows << [ "A few of them", sample ] if sample.present?
    rows << [ "Before it runs", touches_existing? ? "Firefight keeps a copy of these rows for #{COPY_KEPT_FOR.inspect}." : "Nothing is overwritten, so no copy is needed." ]
    rows
  end

  # The copy kept of the rows, as a file, for a member who may read that database now, which the gateway decides and the
  # activity log records like any read of it.
  Copy = Data.define(:text, :filename, :refusal)

  def copy_for(member)
    return Copy.new(text: nil, filename: nil, refusal: "The copy of these rows was dropped once kept for #{COPY_KEPT_FOR.inspect}.") unless copy_kept?

    tool = Integration::Tool.in_workspace(workspace).find { |each| each.action_key == action_key }
    definition = Integrations::DataWrites.for(tool)
    reader = definition && Integrations::DataWrites.read_tool(tool, definition)
    unless reader
      return Copy.new(text: nil, filename: nil, refusal: "The database these rows came from is no longer connected here, so the copy cannot be read. " \
                                                         "An admin can connect it again.")
    end

    AbilityGateway.authorize!(principal: member, action_key: reader.action_key, workspace: workspace, holdable: false,
                              scope: environment_id ? { "environment" => environment_id } : {}, params: { "reads" => "copy of #{rows_words}" },
                              context: { source: AbilityGateway::SOURCE_WEB }).finalize_success!
    Copy.new(text: rows_copy, filename: "#{table_name.to_s.parameterize.presence || 'rows'}-#{copied_at.utc.strftime('%Y%m%d-%H%M')}.txt", refusal: nil)
  rescue AbilityGateway::Denied
    Copy.new(text: nil, filename: nil, refusal: "You may not read that database, so you cannot download its rows. An admin can grant it.")
  end

  # Moves only from proposed, so a second run of the same call never records twice.
  def finish!(status, **columns)
    self.class.where(id: id, status: STATUS_PROPOSED).update_all(status: status, updated_at: Time.current, **columns).positive?.tap { reload }
  end

  # The copy is dropped once kept long enough, leaving the counts.
  def self.drop_expired_copies!
    copy_expired.update_all(rows_copy: nil, copy_cleared_at: Time.current, updated_at: Time.current)
  end
end

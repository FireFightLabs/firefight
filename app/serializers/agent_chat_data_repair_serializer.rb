# A statement Halon ran in this chat that changed rows, with how many, the check before and after, and the copy kept of
# the rows it touched while there is one.
class AgentChatDataRepairSerializer < BaseSerializer
  object_as :repair

  type :string
  def id
    repair.id
  end

  # Such as "42 rows of public.orders".
  type :string
  def rows
    repair.rows_words
  end

  type Integrations::DataWrites::Statement::KINDS.map(&:inspect).join(" | ")
  def kind
    repair.statement_kind
  end

  type :number, optional: true
  def wrong_before
    repair.wrong_before
  end

  type :number, optional: true
  def wrong_after
    repair.wrong_after
  end

  type :string, optional: true
  def check_error
    repair.check_error
  end

  # Until when the copy of the rows is kept, absent once it was dropped or when nothing was copied.
  type :string, optional: true
  def copy_kept_until
    repair.copy_expires_at&.utc&.iso8601 if repair.copy_kept?
  end

  type :string
  def at
    (repair.checked_at || repair.updated_at).utc.iso8601(3)
  end
end

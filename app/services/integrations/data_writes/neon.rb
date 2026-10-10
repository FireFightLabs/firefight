module Integrations
  module DataWrites
    # Neon's server runs one statement, read or write, with run_sql, the statement as sql, and several in one transaction
    # with run_sql_transaction, as sqlStatements, whose rows run_sql reads.
    Neon = Definition.new(
      Tool.new(name: "run_sql", sql: "sql"),
      Tool.new(name: "run_sql_transaction", sql: "sqlStatements", read_tool: "run_sql", read_sql: "sql", many: true)
    )
  end
end

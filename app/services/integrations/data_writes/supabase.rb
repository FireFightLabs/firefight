module Integrations
  module DataWrites
    # Supabase's server runs reads and writes alike with execute_sql, the statement as query.
    Supabase = Definition.new(Tool.new(name: "execute_sql", sql: "query"))
  end
end

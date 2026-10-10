module Integrations
  module DataWrites
    # One SQL statement read far enough to count the rows it touches before it runs: whether it reads, changes rows
    # (an UPDATE, DELETE or INSERT on one table), changes the schema, or is one Firefight cannot count, with why. Strings,
    # quoted names, comments and dollar quotes are skipped, so a keyword inside them never counts. The SQL it writes to
    # read the rows works on Postgres and MySQL alike.
    class Statement
      KIND_READ = "read".freeze
      KIND_UPDATE = "update".freeze
      KIND_DELETE = "delete".freeze
      KIND_INSERT = "insert".freeze
      KIND_SCHEMA = "schema".freeze
      KINDS = [ KIND_READ, KIND_UPDATE, KIND_DELETE, KIND_INSERT, KIND_SCHEMA ].freeze
      # Writes whose rows are counted, copied and checked.
      ROW_WRITES = [ KIND_UPDATE, KIND_DELETE, KIND_INSERT ].freeze
      # Rows an UPDATE or DELETE already holds, which are copied before it runs.
      TOUCHES_EXISTING = [ KIND_UPDATE, KIND_DELETE ].freeze

      READS = %w[SELECT SHOW EXPLAIN DESCRIBE DESC VALUES TABLE].freeze
      SCHEMA = %w[CREATE ALTER DROP RENAME COMMENT GRANT REVOKE ANALYZE VACUUM REINDEX CLUSTER REFRESH].freeze
      # MySQL's words between UPDATE or DELETE and what it names, which change how it waits rather than what it touches.
      MODIFIERS = %w[LOW_PRIORITY QUICK IGNORE].freeze
      WRITING_WORDS = %w[INSERT UPDATE DELETE MERGE].freeze
      TAIL = %w[ORDER LIMIT RETURNING].freeze

      Word = Data.define(:text, :start, :finish, :depth) do
        def upcase = text.upcase
      end

      attr_reader :sql, :kind, :refusal, :target, :where, :tail, :inserted

      def self.parse(sql) = new(sql)

      def initialize(sql)
        @sql = sql.to_s.strip.sub(/[\s;]+\z/, "")
        @refusal = catch(:refused) do
          scan
          classify
          nil
        end
        @kind = nil if @refusal
      end

      def refused? = !@refusal.nil?

      def read? = kind == KIND_READ

      def row_write? = ROW_WRITES.include?(kind)

      def touches_existing? = TOUCHES_EXISTING.include?(kind)

      # The table as the statement names it, such as public.orders, for a person to read.
      def table_name = target.to_s[/\A(?:ONLY\s+)?(\S+)/i, 1]

      # The rows an UPDATE or DELETE touches, in the order and number it touches them.
      def rows_sql = "SELECT * FROM #{target}#{" WHERE #{where}" if where}#{" #{tail}" if tail}"

      # How many rows it touches, counted under COUNT_COLUMN. An INSERT of listed values knows its count without asking.
      def count_sql
        return "SELECT count(*) AS #{COUNT_COLUMN} FROM (#{rows_sql}) AS halon_touched" if touches_existing?

        "SELECT count(*) AS #{COUNT_COLUMN} FROM (#{inserted}) AS halon_inserted" if kind == KIND_INSERT && inserted.is_a?(String)
      end

      # The rows it inserts when it lists them, or nil when they come from a query.
      def known_count = inserted.is_a?(Integer) ? inserted : nil

      def sample_sql(rows) = "SELECT * FROM (#{rows_sql}) AS halon_touched LIMIT #{rows.to_i}"

      # One page of the rows it touches, in a fixed order, so pages read one after another hold each row once.
      def page_sql(rows, offset) = "SELECT * FROM (#{rows_sql}) AS halon_touched ORDER BY 1 LIMIT #{rows.to_i} OFFSET #{offset.to_i}"

      # How many rows a check query returns, which a repair that worked brings to zero. nil when the check is not one
      # query that only reads.
      def self.counting(check)
        statement = parse(check)
        return unless statement.read? && statement.sql.present? && !statement.sql.match?(/\A(?:SHOW|EXPLAIN|DESCRIBE|DESC)\b/i)

        "SELECT count(*) AS #{COUNT_COLUMN} FROM (#{statement.sql}) AS halon_check"
      end

      private

      def refuse!(reason) = throw(:refused, reason)

      def scan
        refuse!("There is no statement to run.") if sql.empty?

        @words = []
        @openings = []
        depth = 0
        index = 0
        while index < sql.length
          char = sql[index]
          following = sql[index + 1]
          if char == "'"
            index = past_quote(index, "'")
          elsif char == '"' || char == "`"
            index = past_quote(index, char)
          elsif char == "-" && following == "-"
            index = sql.index("\n", index) || sql.length
          elsif char == "/" && following == "*"
            closing = sql.index("*/", index + 2) || refuse!("A comment in it is never closed, so it cannot be read.")
            index = closing + 2
          elsif char == "$" && (tag = sql[index..][/\A\$(?:[A-Za-z_]\w*)?\$/])
            closing = sql.index(tag, index + tag.length) || refuse!("A quoted body in it is never closed, so it cannot be read.")
            index = closing + tag.length
          elsif char == "("
            @openings << index if depth.zero?
            depth += 1
            index += 1
          elsif char == ")"
            depth -= 1
            index += 1
          elsif char == ";" && depth.zero?
            refuse!("Run one statement at a time, so the rows each one touches can be counted.")
          elsif char.match?(/[A-Za-z_]/)
            word = sql[index..][/\A[A-Za-z_][\w$]*/]
            @words << Word.new(text: word, start: index, finish: index + word.length, depth: depth)
            index += word.length
          else
            index += 1
          end
        end
      end

      # A quote doubled or escaped with a backslash stays inside it.
      def past_quote(index, quote)
        cursor = index + 1
        while cursor < sql.length
          if sql[cursor] == "\\" && quote == "'"
            cursor += 2
          elsif sql[cursor] == quote
            return cursor + 1 unless sql[cursor + 1] == quote

            cursor += 2
          else
            cursor += 1
          end
        end
        refuse!("A quote in it is never closed, so it cannot be read.")
      end

      def top = @top ||= @words.select { |word| word.depth.zero? }

      def classify
        first = top.first&.upcase
        case first
        when "UPDATE" then update!
        when "DELETE" then delete!
        when "INSERT" then insert!
        when "WITH" then with!
        when "EXPLAIN" then explain!
        when *READS then @kind = KIND_READ
        when *SCHEMA then @kind = KIND_SCHEMA
        when "TRUNCATE" then refuse!("TRUNCATE removes every row with nothing to count or keep. Delete them with a WHERE, at most #{ActiveSupport::NumberHelper.number_to_delimited(COPY_LIMIT)} at a time, instead.")
        else refuse!("Firefight cannot tell which rows a #{first || 'statement like this'} changes, so it cannot count them first. Use one UPDATE, DELETE or INSERT on one table.")
        end
      end

      # A WITH only reads unless one of its parts writes, which Firefight cannot count. FOR UPDATE locks rows a read
      # returns, and is still a read.
      def with!
        writing = @words.each_with_index.any? do |word, index|
          WRITING_WORDS.include?(word.upcase) && !(word.upcase == "UPDATE" && @words[index - 1]&.upcase == "FOR")
        end
        refuse!("A WITH that writes cannot be counted first. Write it as one UPDATE, DELETE or INSERT on one table.") if writing
        @kind = KIND_READ
      end

      # EXPLAIN ANALYZE runs the statement it explains.
      def explain!
        runs = @words.any? { |word| word.upcase == "ANALYZE" } && top.any? { |word| WRITING_WORDS.include?(word.upcase) }
        refuse!("EXPLAIN ANALYZE runs the write it explains. Leave out ANALYZE to see the plan.") if runs
        @kind = KIND_READ
      end

      def update!
        named = after_modifiers(1)
        set = clause("SET") || refuse!("An UPDATE needs a SET.")
        @target = one_table(sql[named...set.start])
        refuse!("An UPDATE with FROM changes rows by another table's, which cannot be counted first. Update one table with a WHERE.") if clause("FROM", after: set)
        rest_from(set)
        @kind = KIND_UPDATE
      end

      def delete!
        from = top[after_modifiers_index(1)]
        refuse!("A DELETE that names more than one table cannot be counted first. Delete from one table with a WHERE.") unless from&.upcase == "FROM"
        ending = [ clause("USING", after: from), clause("WHERE", after: from), *TAIL.map { |word| clause(word, after: from) } ].compact.min_by(&:start)
        refuse!("A DELETE with USING removes rows by another table's, which cannot be counted first. Delete from one table with a WHERE.") if ending&.upcase == "USING"
        @target = one_table(sql[from.finish...(ending&.start || sql.length)])
        rest_from(from)
        @kind = KIND_DELETE
      end

      def insert!
        conflict = top.each_cons(2).any? { |word, following| (word.upcase == "DO" && following.upcase == "UPDATE") || (word.upcase == "DUPLICATE" && following.upcase == "KEY") }
        refuse!("An INSERT that updates rows already there cannot be counted first. Insert only new rows, or update the others on their own.") if conflict

        ending = top.find { |word| %w[ON RETURNING].include?(word.upcase) }&.start || sql.length
        values = top.find { |word| word.upcase == "VALUES" }
        query = top.drop(1).find { |word| %w[SELECT WITH].include?(word.upcase) }
        @inserted = if values && (query.nil? || values.start < query.start)
          @openings.count { |opening| opening > values.start && opening < ending }
        elsif query
          sql[query.start...ending].strip
        elsif top.each_cons(2).any? { |word, following| word.upcase == "DEFAULT" && following.upcase == "VALUES" }
          1
        else
          refuse!("Firefight cannot tell how many rows this INSERT adds. List the values or insert from one SELECT.")
        end
        @target = sql[/\AINSERT\s+(?:IGNORE\s+)?(?:INTO\s+)?(\S+)/i, 1]
        @kind = KIND_INSERT
      end

      # The rest of an UPDATE or DELETE after the word its clauses follow: its WHERE, then any ORDER BY and LIMIT, which
      # MySQL lets a write take, and never what it returns.
      def rest_from(word)
        where = clause("WHERE", after: word)
        tail_start = TAIL.filter_map { |name| clause(name, after: where || word) }.reject { |found| found.upcase == "RETURNING" }.min_by(&:start)
        returning = clause("RETURNING", after: where || word)
        refuse!("WHERE CURRENT OF reaches a cursor's row, which cannot be counted first. Name the rows with a WHERE.") if where && sql[where.finish..].match?(/\A\s+CURRENT\s+OF\b/i)

        @where = sql[where.finish...(tail_start || returning)&.start || sql.length].strip if where
        @tail = sql[tail_start.start...(returning&.start || sql.length)].strip if tail_start
      end

      def clause(name, after: nil) = top.find { |word| word.upcase == name && (after.nil? || word.start > after.start) }

      def after_modifiers_index(from)
        index = from
        index += 1 while MODIFIERS.include?(top[index]&.upcase)
        index
      end

      def after_modifiers(from)
        before = top[after_modifiers_index(from) - 1]
        before.finish
      end

      def one_table(text)
        named = text.to_s.strip
        refuse!("It names no table.") if named.empty?
        joins = named.match?(/\bJOIN\b/i) || depth_zero_comma?(named)
        refuse!("A write that names more than one table cannot be counted first. Write to one table with a WHERE.") if joins
        named
      end

      def depth_zero_comma?(text)
        depth = 0
        text.each_char.any? do |char|
          depth += 1 if char == "("
          depth -= 1 if char == ")"
          char == "," && depth.zero?
        end
      end
    end
  end
end

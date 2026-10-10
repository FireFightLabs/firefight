require "test_helper"

class Integrations::DataWrites::StatementTest < ActiveSupport::TestCase
  Statement = Integrations::DataWrites::Statement

  test "an UPDATE on one table is read into the rows it touches, its WHERE kept as written" do
    statement = Statement.parse("update public.orders o set status = 'x;y' where o.id in (select id from refunds where note = 'it''s');")

    assert_equal Statement::KIND_UPDATE, statement.kind
    assert_equal "public.orders", statement.table_name
    assert_equal "SELECT * FROM public.orders o WHERE o.id in (select id from refunds where note = 'it''s')", statement.rows_sql
    assert_equal "SELECT count(*) AS halon_rows FROM (#{statement.rows_sql}) AS halon_touched", statement.count_sql
    assert_equal "SELECT * FROM (#{statement.rows_sql}) AS halon_touched ORDER BY 1 LIMIT 100 OFFSET 200", statement.page_sql(100, 200)
  end

  test "a DELETE keeps its ORDER BY and LIMIT, which decide which rows it takes, and never what it returns" do
    statement = Statement.parse("DELETE FROM jobs WHERE state = 'dead' ORDER BY id LIMIT 100 RETURNING id")

    assert_equal Statement::KIND_DELETE, statement.kind
    assert_equal "SELECT * FROM jobs WHERE state = 'dead' ORDER BY id LIMIT 100", statement.rows_sql
  end

  test "a keyword inside a comment or a quoted name never counts" do
    statement = Statement.parse(%(UPDATE "Orders" SET a = 1 -- WHERE nothing\n WHERE id = 3))

    assert_equal %(SELECT * FROM "Orders" WHERE id = 3), statement.rows_sql
  end

  test "an INSERT of listed values knows its count, and one from a query counts the query" do
    listed = Statement.parse("INSERT INTO flags (name) VALUES ('a'), ('b'), ('c')")
    assert_equal 3, listed.known_count
    assert_nil listed.count_sql

    queried = Statement.parse("INSERT INTO archive SELECT * FROM orders WHERE created_at < '2020-01-01'")
    assert_equal "SELECT count(*) AS halon_rows FROM (SELECT * FROM orders WHERE created_at < '2020-01-01') AS halon_inserted", queried.count_sql
  end

  test "a read, including a lock it takes, and a schema change are told apart from a write" do
    assert Statement.parse("SELECT * FROM orders FOR UPDATE").read?
    assert_equal Statement::KIND_SCHEMA, Statement.parse("ALTER TABLE orders ADD COLUMN note text").kind
  end

  test "what cannot be counted first is refused with how to write it instead" do
    {
      "UPDATE a SET x = b.x FROM b WHERE a.id = b.id" => "An UPDATE with FROM",
      "DELETE t1 FROM t1 JOIN t2 ON t1.id = t2.id" => "A DELETE that names more than one table",
      "UPDATE orders, items SET a = 1" => "names more than one table",
      "INSERT INTO t (a) VALUES (1) ON CONFLICT (a) DO UPDATE SET a = 2" => "updates rows already there",
      "WITH gone AS (DELETE FROM x RETURNING *) SELECT count(*) FROM gone" => "A WITH that writes",
      "TRUNCATE orders" => "at most 1,000 at a time",
      "UPDATE orders SET a = 1; DELETE FROM orders" => "Run one statement at a time",
      "EXPLAIN (ANALYZE) DELETE FROM orders" => "EXPLAIN ANALYZE runs the write",
      "UPDATE orders SET note = 'open" => "never closed",
      "CALL refresh_totals()" => "Firefight cannot tell which rows a CALL changes"
    }.each do |sql, words|
      statement = Statement.parse(sql)
      assert statement.refused?, sql
      assert_includes statement.refusal, words, sql
    end
  end

  test "a check is counted only when it is one query that reads" do
    assert_equal "SELECT count(*) AS halon_rows FROM (SELECT id FROM orders WHERE currency IS NULL) AS halon_check",
                 Statement.counting("SELECT id FROM orders WHERE currency IS NULL")
    assert_nil Statement.counting("DELETE FROM orders")
    assert_nil Statement.counting("EXPLAIN SELECT 1")
  end

  test "a count is found in any shape a provider answers it in" do
    assert_equal 42, Integrations::DataWrites.count_in('[{"halon_rows": 42}]')
    assert_equal 7, Integrations::DataWrites.count_in("SELECT count(*) AS halon_rows FROM (x)\nhalon_rows\n7")
    assert_nil Integrations::DataWrites.count_in("No rows.")
  end
end

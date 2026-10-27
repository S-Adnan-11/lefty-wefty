require "json"

module SchemaContract
  def self.expression(connection, table, sql)
    # Let PostgreSQL fold equivalent casts without removing boolean grouping.
    plan = connection.exec("EXPLAIN (VERBOSE, FORMAT JSON, COSTS OFF) SELECT (#{sql}) FROM public.#{connection.quote_ident(table)}").getvalue(0, 0)
    JSON.parse(plan).fetch(0).fetch("Plan").fetch("Output").fetch(0)
  end

  def self.capture(connection)
    constraints = connection.exec(<<~SQL).values.map do |table, name, kind, definition, sql, *flags|
      SELECT r.relname, c.conname, c.contype, pg_get_constraintdef(c.oid), pg_get_expr(c.conbin, c.conrelid),
             c.convalidated, c.connoinherit, c.condeferrable, c.condeferred
        FROM pg_constraint c JOIN pg_class r ON r.oid=c.conrelid
       WHERE c.connamespace='public'::regnamespace ORDER BY r.relname, c.conname
    SQL
      [ table, name, kind, kind == "c" ? expression(connection, table, sql) : definition, *flags ]
    end
    functions = connection.exec(<<~SQL).values.map do |*metadata, source|
      SELECT p.proname, pg_get_function_identity_arguments(p.oid), p.prorettype::regtype::text, l.lanname,
             p.prokind, p.provolatile, p.prosecdef, p.proisstrict, p.proleakproof, p.proparallel, p.proconfig::text, p.prosrc
        FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
       WHERE p.pronamespace='public'::regnamespace ORDER BY p.proname, p.proargtypes
    SQL
      [ *metadata, source.gsub("\r\n", "\n").strip ]
    end
    indexes = connection.exec(<<~SQL).values.map do |table, name, definition, predicate, *flags|
      SELECT r.relname, x.relname, pg_get_indexdef(i.indexrelid), pg_get_expr(i.indpred, i.indrelid),
             i.indisunique, i.indisvalid, i.indisready, i.indnullsnotdistinct
        FROM pg_index i JOIN pg_class r ON r.oid=i.indrelid JOIN pg_class x ON x.oid=i.indexrelid
       WHERE r.relnamespace='public'::regnamespace ORDER BY r.relname, x.relname
    SQL
      [ table, name, definition.partition(" WHERE ").first, predicate && expression(connection, table, predicate), *flags ]
    end
    {
      constraints: constraints, functions: functions, indexes: indexes,
      triggers: connection.exec("SELECT tgrelid::regclass::text, tgname, pg_get_triggerdef(oid) FROM pg_trigger WHERE NOT tgisinternal AND tgrelid IN (SELECT oid FROM pg_class WHERE relnamespace='public'::regnamespace) ORDER BY 1,2").values
    }
  end
end

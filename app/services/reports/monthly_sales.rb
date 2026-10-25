module Reports
  class MonthlySales
    class InvalidRange < StandardError; end
    MAX_MONTHS = 36
    Row = Data.define(:month, :sale_count, :units, :total_minor)
    Result = Data.define(:first_month, :last_month, :current_month, :generated_at, :rows, :sale_count, :units, :total_minor)

    # confirmed_at is a UTC wall-clock timestamp WITHOUT time zone. Both the
    # predicate and grouping explicitly convert it; the session zone is irrelevant.
    SQL = <<~SQL.freeze
      WITH months AS (
        SELECT month_start::date AS month
        FROM generate_series($2::date::timestamp, $3::date::timestamp, interval '1 month') AS month_start
      ), qualifying_orders AS (
        SELECT id, total_minor,
          date_trunc('month', confirmed_at AT TIME ZONE 'UTC' AT TIME ZONE $4)::date AS month
        FROM orders
        WHERE business_id = $1 AND state = 'confirmed'
          AND confirmed_at >= (($2::date::timestamp AT TIME ZONE $4) AT TIME ZONE 'UTC')
          AND confirmed_at < ((($3::date::timestamp + interval '1 month') AT TIME ZONE $4) AT TIME ZONE 'UTC')
      ), order_units AS (
        -- One row per order BEFORE joining its total: equal-value sales remain
        -- separate, while multiple items cannot multiply an order's value.
        SELECT items.order_id, SUM(items.quantity) AS units
        FROM order_items items
        INNER JOIN qualifying_orders orders ON orders.id = items.order_id
        WHERE items.business_id = $1
        GROUP BY items.order_id
      ), monthly AS (
        SELECT orders.month, COUNT(*) AS sale_count,
          SUM(units.units) AS units, SUM(orders.total_minor) AS total_minor
        FROM qualifying_orders orders
        INNER JOIN order_units units ON units.order_id = orders.id
        GROUP BY orders.month
      )
      SELECT months.month, COALESCE(monthly.sale_count, 0) AS sale_count,
        COALESCE(monthly.units, 0) AS units, COALESCE(monthly.total_minor, 0) AS total_minor
      FROM months LEFT JOIN monthly ON monthly.month = months.month
      ORDER BY months.month
    SQL

    def self.call(business:, actor:, first_month: nil, last_month: nil, now: Time.current)
      Sales::Draft.authorize!(business, actor)
      current = now.in_time_zone(business.timezone).to_date.beginning_of_month
      first = parse_month(first_month, current << 11)
      last = parse_month(last_month, current)
      span = (last.year - first.year) * 12 + last.month - first.month + 1
      raise InvalidRange, "First month must be on or before last month." if span < 1
      raise InvalidRange, "Choose at most #{MAX_MONTHS} months at a time." if span > MAX_MONTHS

      binds = [
        ActiveRecord::Relation::QueryAttribute.new("business_id", business.id, ActiveRecord::Type::Integer.new(limit: 8)),
        ActiveRecord::Relation::QueryAttribute.new("first_month", first.iso8601, ActiveRecord::Type::String.new),
        ActiveRecord::Relation::QueryAttribute.new("last_month", last.iso8601, ActiveRecord::Type::String.new),
        ActiveRecord::Relation::QueryAttribute.new("timezone", business.timezone, ActiveRecord::Type::String.new)
      ]
      rows = ApplicationRecord.with_connection do |connection|
        connection.select_all(SQL, "Monthly sales", binds).map do |row|
          # PostgreSQL SUM(bigint) is numeric. Integer conversion stays exact.
          Row.new(month: row.fetch("month").to_date, sale_count: row.fetch("sale_count").to_i,
            units: row.fetch("units").to_i, total_minor: row.fetch("total_minor").to_i)
        end
      end
      Result.new(first_month: first, last_month: last, current_month: current, generated_at: now, rows: rows,
        sale_count: rows.sum(&:sale_count), units: rows.sum(&:units), total_minor: rows.sum(&:total_minor))
    end

    def self.parse_month(value, fallback)
      return fallback if value.nil?
      text = value.to_s
      unless /\A[0-9]{4}-(0[1-9]|1[0-2])\z/.match?(text) && text.first(4).to_i.positive?
        raise InvalidRange, "Enter both months as YYYY-MM, with a year from 0001 to 9999."
      end
      Date.iso8601("#{text}-01")
    end
    private_class_method :parse_month
  end
end

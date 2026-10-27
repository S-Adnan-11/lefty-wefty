require "test_helper"
require_relative "../../script/ci/schema_contract"

class SchemaContractTest < ActiveSupport::TestCase
  test "equivalent PostgreSQL text-array casts normalize consistently" do
    connection = ActiveRecord::Base.connection.raw_connection
    array_cast = "kind = ANY (ARRAY['opening'::character varying, 'receipt'::character varying]::text[])"
    element_cast = "kind = ANY (ARRAY[('opening'::character varying)::text, ('receipt'::character varying)::text])"
    assert_equal SchemaContract.expression(connection, "inventory_logs", array_cast), SchemaContract.expression(connection, "inventory_logs", element_cast)
  end

  test "logical grouping remains part of the schema contract" do
    connection = ActiveRecord::Base.connection.raw_connection
    left = "quantity_delta > 0 AND (order_item_id IS NULL OR reason IS NULL)"
    right = "(quantity_delta > 0 AND order_item_id IS NULL) OR reason IS NULL"
    refute_equal SchemaContract.expression(connection, "inventory_logs", left), SchemaContract.expression(connection, "inventory_logs", right)
  end
end

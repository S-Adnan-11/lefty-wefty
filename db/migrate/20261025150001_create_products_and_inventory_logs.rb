class CreateProductsAndInventoryLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false, limit: 160
      t.string :sku, null: false, limit: 64
      t.bigint :price_minor, null: false
      t.integer :quantity, null: false, default: 0
      t.integer :low_stock_threshold, null: false, default: 0
      t.datetime :archived_at
      t.timestamps
    end
    add_index :products, [ :business_id, :sku ], unique: true
    add_index :products, [ :business_id, :id ], unique: true
    add_index :products, [ :business_id, :archived_at, :name ]
    add_check_constraint :products, "length(btrim(name)) > 0", name: "product_name_present"
    add_check_constraint :products, "sku ~ '^[A-Z0-9][A-Z0-9._-]*$'", name: "product_normalized_sku"
    add_check_constraint :products, "price_minor BETWEEN 1 AND 999999999999", name: "product_price_range"
    add_check_constraint :products, "quantity >= 0 AND low_stock_threshold >= 0", name: "product_stock_nonnegative"

    create_table :inventory_logs do |t|
      t.references :business, null: false, foreign_key: true
      t.bigint :product_id, null: false
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.uuid :operation_key, null: false
      t.string :kind, null: false, limit: 16
      t.integer :quantity_delta, null: false
      t.integer :resulting_balance, null: false
      t.string :reason, null: false, limit: 500
      t.datetime :created_at, null: false
    end
    add_index :inventory_logs, [ :business_id, :operation_key ], unique: true
    add_index :inventory_logs, [ :business_id, :product_id, :id ]
    add_foreign_key :inventory_logs, :products, column: [ :business_id, :product_id ], primary_key: [ :business_id, :id ]
    add_foreign_key :inventory_logs, :businesses, column: [ :business_id, :actor_id ], primary_key: [ :id, :owner_id ]
    add_check_constraint :inventory_logs, "quantity_delta <> 0 AND resulting_balance >= 0", name: "movement_valid_quantities"
    add_check_constraint :inventory_logs, "kind IN ('opening', 'receipt', 'adjustment') AND (kind = 'adjustment' OR quantity_delta > 0)", name: "movement_valid_kind"
    add_check_constraint :inventory_logs, "length(btrim(reason)) > 0", name: "movement_reason_present"

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE FUNCTION prevent_inventory_log_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
          BEGIN
            RAISE EXCEPTION 'Inventory history is append-only';
          END;
          $$;
          CREATE TRIGGER inventory_logs_append_only
            BEFORE UPDATE OR DELETE ON inventory_logs
            FOR EACH ROW EXECUTE FUNCTION prevent_inventory_log_mutation();
        SQL
      end
      dir.down do
        execute "DROP TRIGGER inventory_logs_append_only ON inventory_logs"
        execute "DROP FUNCTION prevent_inventory_log_mutation()"
      end
    end
  end
end

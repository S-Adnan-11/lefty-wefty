class CreateSales < ActiveRecord::Migration[8.1]
  def up
    create_table :orders do |t|
      t.references :business, null: false, foreign_key: true
      t.uuid :submission_key, null: false
      t.string :creation_digest, null: false, limit: 64
      t.string :state, null: false, default: "draft", limit: 16
      t.integer :revision, null: false, default: 0
      t.uuid :review_token, null: false
      t.jsonb :quote, null: false
      t.bigint :total_minor, null: false
      t.datetime :confirmed_at
      t.bigint :confirmed_by_id
      t.datetime :voided_at
      t.bigint :voided_by_id
      t.string :void_reason, limit: 500
      t.timestamps
    end
    add_index :orders, [ :business_id, :submission_key ], unique: true
    add_index :orders, [ :business_id, :id ], unique: true
    add_index :orders, [ :business_id, :state, :id ]
    %i[confirmed_by_id voided_by_id].each do |actor|
      add_foreign_key :orders, :businesses, column: [ :business_id, actor ], primary_key: [ :id, :owner_id ]
    end
    add_check_constraint :orders, "revision >= 0 AND total_minor BETWEEN 1 AND 9223372036854775807 AND jsonb_typeof(quote) = 'array'", name: "order_valid_review"
    add_check_constraint :orders, <<~SQL.squish, name: "order_valid_state"
      (state = 'draft' AND confirmed_at IS NULL AND confirmed_by_id IS NULL AND voided_at IS NULL AND voided_by_id IS NULL AND void_reason IS NULL) OR
      (state = 'confirmed' AND confirmed_at IS NOT NULL AND confirmed_by_id IS NOT NULL AND voided_at IS NULL AND voided_by_id IS NULL AND void_reason IS NULL) OR
      (state = 'voided' AND confirmed_at IS NOT NULL AND confirmed_by_id IS NOT NULL AND voided_at IS NOT NULL AND voided_at >= confirmed_at AND voided_by_id IS NOT NULL AND void_reason IS NOT NULL AND length(btrim(void_reason)) > 0)
    SQL

    create_table :order_items do |t|
      t.bigint :business_id, null: false
      t.bigint :order_id, null: false
      t.bigint :product_id, null: false
      t.integer :quantity, null: false
      t.string :product_name, limit: 160
      t.string :product_sku, limit: 64
      t.bigint :unit_price_minor
      t.bigint :line_total_minor
    end
    add_index :order_items, [ :order_id, :product_id ], unique: true
    add_index :order_items, [ :business_id, :id, :product_id ], unique: true
    add_foreign_key :order_items, :orders, column: [ :business_id, :order_id ], primary_key: [ :business_id, :id ]
    add_foreign_key :order_items, :products, column: [ :business_id, :product_id ], primary_key: [ :business_id, :id ]
    add_check_constraint :order_items, "quantity > 0", name: "sale_item_positive_quantity"
    add_check_constraint :order_items, <<~SQL.squish, name: "sale_item_valid_snapshot"
      (product_name IS NULL AND product_sku IS NULL AND unit_price_minor IS NULL AND line_total_minor IS NULL) OR
      (product_name IS NOT NULL AND length(btrim(product_name)) > 0 AND product_sku IS NOT NULL AND length(btrim(product_sku)) > 0
       AND unit_price_minor IS NOT NULL AND unit_price_minor BETWEEN 1 AND 999999999999
       AND line_total_minor IS NOT NULL AND line_total_minor > 0 AND line_total_minor::numeric = quantity::numeric * unit_price_minor::numeric)
    SQL

    add_column :inventory_logs, :order_item_id, :bigint
    add_column :inventory_logs, :reversal_of_id, :bigint
    add_index :inventory_logs, [ :order_item_id, :kind ], unique: true, where: "order_item_id IS NOT NULL"
    add_index :inventory_logs, :reversal_of_id, unique: true, where: "reversal_of_id IS NOT NULL"
    add_index :inventory_logs, [ :business_id, :order_item_id, :product_id, :id ], unique: true, name: "movement_sale_identity"
    add_foreign_key :inventory_logs, :order_items, column: [ :business_id, :order_item_id, :product_id ], primary_key: [ :business_id, :id, :product_id ]
    add_foreign_key :inventory_logs, :inventory_logs,
      column: [ :business_id, :order_item_id, :product_id, :reversal_of_id ],
      primary_key: [ :business_id, :order_item_id, :product_id, :id ], name: "movement_reverses_same_item"
    remove_check_constraint :inventory_logs, name: "movement_valid_kind"
    add_check_constraint :inventory_logs, <<~SQL.squish, name: "movement_valid_kind"
      (kind IN ('opening', 'receipt', 'adjustment') AND order_item_id IS NULL AND reversal_of_id IS NULL AND (kind = 'adjustment' OR quantity_delta > 0)) OR
      (kind = 'sale' AND order_item_id IS NOT NULL AND reversal_of_id IS NULL AND quantity_delta < 0) OR
      (kind = 'sale_void' AND order_item_id IS NOT NULL AND reversal_of_id IS NOT NULL AND quantity_delta > 0)
    SQL

    execute <<~SQL
      CREATE FUNCTION protect_sale_history() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE parent_state text;
      BEGIN
        IF TG_TABLE_NAME = 'orders' THEN
          IF OLD.state <> 'draft' THEN
            IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Recorded sales cannot be deleted'; END IF;
            IF NOT (OLD.state = 'confirmed' AND NEW.state = 'voided' AND
              (to_jsonb(OLD) - ARRAY['state','voided_at','voided_by_id','void_reason','updated_at']) =
              (to_jsonb(NEW) - ARRAY['state','voided_at','voided_by_id','void_reason','updated_at'])) THEN
              RAISE EXCEPTION 'Recorded sales are immutable';
            END IF;
          ELSIF TG_OP = 'UPDATE' AND (NEW.business_id <> OLD.business_id OR NEW.submission_key <> OLD.submission_key OR NEW.creation_digest <> OLD.creation_digest) THEN
            RAISE EXCEPTION 'Sale submission identity is immutable';
          END IF;
        ELSE
          IF TG_OP <> 'INSERT' THEN
            SELECT state INTO parent_state FROM orders WHERE id = OLD.order_id FOR UPDATE;
            IF parent_state <> 'draft' THEN RAISE EXCEPTION 'Recorded sale items are immutable'; END IF;
          END IF;
          IF TG_OP <> 'DELETE' THEN
            SELECT state INTO parent_state FROM orders WHERE id = NEW.order_id FOR UPDATE;
            IF parent_state <> 'draft' THEN RAISE EXCEPTION 'Recorded sale items are immutable'; END IF;
          END IF;
        END IF;
        IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
      END; $$;
      CREATE TRIGGER orders_protect_history BEFORE UPDATE OR DELETE ON orders
        FOR EACH ROW EXECUTE FUNCTION protect_sale_history();
      CREATE TRIGGER order_items_protect_history BEFORE INSERT OR UPDATE OR DELETE ON order_items
        FOR EACH ROW EXECUTE FUNCTION protect_sale_history();

      CREATE FUNCTION validate_recorded_sale() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE sale_id bigint; sale orders%ROWTYPE; item_count bigint;
      BEGIN
        IF TG_TABLE_NAME = 'orders' THEN sale_id := COALESCE(NEW.id, OLD.id);
        ELSIF TG_TABLE_NAME = 'order_items' THEN sale_id := COALESCE(NEW.order_id, OLD.order_id);
        ELSE SELECT order_id INTO sale_id FROM order_items WHERE id = NEW.order_item_id;
        END IF;
        SELECT * INTO sale FROM orders WHERE id = sale_id;
        IF NOT FOUND THEN RETURN NULL; END IF;
        SELECT count(*) INTO item_count FROM order_items WHERE order_id = sale_id;
        IF item_count = 0 THEN RAISE EXCEPTION 'A sale requires items'; END IF;
        IF sale.state = 'draft' THEN
          IF EXISTS (SELECT 1 FROM order_items i LEFT JOIN inventory_logs l ON l.order_item_id = i.id
                     WHERE i.order_id = sale_id AND (i.unit_price_minor IS NOT NULL OR l.id IS NOT NULL)) THEN
            RAISE EXCEPTION 'Drafts cannot have recorded snapshots or stock movements';
          END IF;
        ELSE
          IF EXISTS (SELECT 1 FROM order_items WHERE order_id = sale_id AND unit_price_minor IS NULL)
             OR sale.total_minor <> (SELECT sum(line_total_minor) FROM order_items WHERE order_id = sale_id) THEN
            RAISE EXCEPTION 'Sale snapshots and total must agree';
          END IF;
          IF (SELECT count(*) FROM inventory_logs l JOIN order_items i ON i.id = l.order_item_id
              WHERE i.order_id = sale_id AND l.kind = 'sale' AND l.quantity_delta = -i.quantity AND l.actor_id = sale.confirmed_by_id) <> item_count THEN
            RAISE EXCEPTION 'Sale deductions must match every item';
          END IF;
          IF (SELECT count(*) FROM inventory_logs l JOIN order_items i ON i.id = l.order_item_id
              JOIN inventory_logs original ON original.id = l.reversal_of_id AND original.kind = 'sale'
              WHERE i.order_id = sale_id AND l.kind = 'sale_void' AND l.quantity_delta = i.quantity AND l.actor_id = sale.voided_by_id)
              <> (CASE WHEN sale.state = 'voided' THEN item_count ELSE 0 END) THEN
            RAISE EXCEPTION 'Sale reversals must match the void state and every item';
          END IF;
        END IF;
        RETURN NULL;
      END; $$;
      CREATE CONSTRAINT TRIGGER orders_consistent AFTER INSERT OR UPDATE ON orders
        DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_recorded_sale();
      CREATE CONSTRAINT TRIGGER order_items_consistent AFTER INSERT OR UPDATE OR DELETE ON order_items
        DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_recorded_sale();
      CREATE CONSTRAINT TRIGGER sale_movements_consistent AFTER INSERT ON inventory_logs
        DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_recorded_sale();
    SQL
  end

  def down
    execute "DROP TRIGGER sale_movements_consistent ON inventory_logs"
    execute "DROP FUNCTION validate_recorded_sale() CASCADE"
    execute "DROP FUNCTION protect_sale_history() CASCADE"
    remove_foreign_key :inventory_logs, name: "movement_reverses_same_item"
    remove_foreign_key :inventory_logs, :order_items
    remove_index :inventory_logs, name: "movement_sale_identity"
    remove_column :inventory_logs, :reversal_of_id
    remove_column :inventory_logs, :order_item_id
    remove_check_constraint :inventory_logs, name: "movement_valid_kind"
    add_check_constraint :inventory_logs, "kind IN ('opening', 'receipt', 'adjustment') AND (kind = 'adjustment' OR quantity_delta > 0)", name: "movement_valid_kind"
    drop_table :order_items
    drop_table :orders
  end
end

class ValidateSaleMovementLinks < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION validate_sale_movement_link() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE sale_state text; sold_quantity integer; original_kind text;
      BEGIN
        IF NEW.order_item_id IS NULL THEN RETURN NULL; END IF;
        SELECT o.state, i.quantity INTO sale_state, sold_quantity
          FROM order_items i JOIN orders o ON o.id = i.order_id WHERE i.id = NEW.order_item_id;
        IF NEW.kind = 'sale' THEN
          IF sale_state NOT IN ('confirmed', 'voided') OR NEW.quantity_delta <> -sold_quantity THEN
            RAISE EXCEPTION 'Sale movement must deduct the recorded quantity of a confirmed sale';
          END IF;
        ELSE
          SELECT kind INTO original_kind FROM inventory_logs WHERE id = NEW.reversal_of_id;
          IF sale_state <> 'voided' OR NEW.quantity_delta <> sold_quantity OR original_kind <> 'sale' THEN
            RAISE EXCEPTION 'Sale reversal must restore the recorded quantity of a voided sale';
          END IF;
        END IF;
        RETURN NULL;
      END; $$;
      CREATE CONSTRAINT TRIGGER sale_movement_valid_link AFTER INSERT ON inventory_logs
        DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_sale_movement_link();
    SQL
  end

  def down
    execute "DROP TRIGGER sale_movement_valid_link ON inventory_logs"
    execute "DROP FUNCTION validate_sale_movement_link()"
  end
end

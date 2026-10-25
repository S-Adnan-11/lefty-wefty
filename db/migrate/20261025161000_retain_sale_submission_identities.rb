class RetainSaleSubmissionIdentities < ActiveRecord::Migration[8.1]
  def up
    create_table :sale_submissions do |t|
      t.references :business, null: false, foreign_key: true
      t.uuid :submission_key, null: false
      t.string :creation_digest, null: false, limit: 64
      t.bigint :order_id
    end
    add_index :sale_submissions, [ :business_id, :submission_key ], unique: true
    add_index :sale_submissions, :order_id, unique: true
    add_foreign_key :sale_submissions, :orders, column: [ :business_id, :order_id ], primary_key: [ :business_id, :id ]
    execute <<~SQL
      INSERT INTO sale_submissions (business_id, submission_key, creation_digest, order_id)
      SELECT business_id, submission_key, creation_digest, id FROM orders;
      CREATE FUNCTION protect_sale_submission() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Sale submission identities are retained'; END IF;
        IF (to_jsonb(OLD) - 'order_id') <> (to_jsonb(NEW) - 'order_id') OR NEW.order_id IS NOT NULL THEN
          RAISE EXCEPTION 'Sale submission identity is immutable';
        END IF;
        RETURN NEW;
      END; $$;
      CREATE TRIGGER sale_submissions_retained BEFORE UPDATE OR DELETE ON sale_submissions
        FOR EACH ROW EXECUTE FUNCTION protect_sale_submission();
    SQL
  end

  def down
    drop_table :sale_submissions
    execute "DROP FUNCTION protect_sale_submission()"
  end
end

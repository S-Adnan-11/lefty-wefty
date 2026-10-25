class CreateBusinesses < ActiveRecord::Migration[8.1]
  def change
    create_table :businesses do |t|
      t.references :owner, null: false, index: { unique: true }, foreign_key: { to_table: :users }
      t.string :name, null: false, limit: 120
      t.string :currency, null: false, default: "NGN", limit: 3
      t.string :timezone, null: false, default: "Africa/Lagos", limit: 100
      t.timestamps
    end
    add_index :businesses, [ :id, :owner_id ], unique: true
    add_check_constraint :businesses, "length(btrim(name)) > 0", name: "business_name_present"
    add_check_constraint :businesses, "currency = 'NGN' AND timezone = 'Africa/Lagos'", name: "business_supported_defaults"
  end
end

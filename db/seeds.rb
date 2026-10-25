abort "Fictional sample data is only available in development or test" unless Rails.env.local?

[
  [ "cedar@example.test", "Cedar Stationery", [ [ "Notebook", "BOOK-1", 125000, 8, 10 ], [ "Pencil", "PEN-1", 25000, 5, 3 ] ] ],
  [ "river@example.test", "River Desk Supplies", [ [ "Sketchbook", "BOOK-1", 200000, 4, 12 ], [ "Eraser", "ERASE-1", 15000, 3, 0 ] ] ]
].each do |email, name, products|
  User.transaction do
    owner = User.find_or_create_by!(email_address: email) do |user|
      # No shared sample password. Use a local mail preview to choose one.
      user.password = SecureRandom.base64(32)
    end
    business = owner.business || Business.create!(owner: owner, name: name)
    products.each do |product_name, sku, price, threshold, opening|
      next if business.products.exists?(sku: sku)
      product = business.products.new(name: product_name, sku: sku, price_minor: price, low_stock_threshold: threshold)
      unless Products::Create.call(product: product, actor: owner, opening_quantity: opening)
        raise ActiveRecord::RecordInvalid, product
      end
    end
  end
end

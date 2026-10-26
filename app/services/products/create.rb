module Products
  class Create
    def self.call(product:, actor:, opening_quantity:)
      generated = product.sku.blank?
      attempts = 0
      begin
        attempts += 1
        result = create(product: product, actor: actor, opening_quantity: opening_quantity)
        if !result && generated && product.errors.of_kind?(:sku, :taken) && attempts < 5
          product.sku = nil
          product.errors.clear
          raise ActiveRecord::RecordNotUnique
        end
        result
      rescue ActiveRecord::RecordNotUnique
        if generated && attempts < 5
          product.sku = nil
          product.errors.clear
          retry
        end
        product.errors.add(:sku, "could not be assigned. Try again or enter your own product code.")
        false
      end
    end

    def self.create(product:, actor:, opening_quantity:)
      unless opening_quantity.to_s.match?(/\A\d+\z/) && opening_quantity.to_i <= Product::MAX_QUANTITY
        product.errors.add(:base, "Starting stock must be a whole number between 0 and #{Product::MAX_QUANTITY}")
        return false
      end

      Product.transaction(requires_new: true) do
        product.save!
        if opening_quantity.to_i.positive?
          Stock::Apply.call(business: product.business, actor: actor, product_id: product.id,
            change: StockChange.new(kind: "opening", quantity: opening_quantity, operation_key: SecureRandom.uuid))
        end
      end
      true
    rescue ActiveRecord::RecordInvalid, Stock::Apply::Rejected => error
      product.errors.add(:base, error.message) if product.errors.empty?
      false
    end
  end
end

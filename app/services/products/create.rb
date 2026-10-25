module Products
  class Create
    def self.call(product:, actor:, opening_quantity:)
      unless opening_quantity.to_s.match?(/\A\d+\z/) && opening_quantity.to_i <= Product::MAX_QUANTITY
        product.errors.add(:base, "Opening quantity must be a whole number between 0 and #{Product::MAX_QUANTITY}")
        return false
      end

      Product.transaction do
        product.save!
        if opening_quantity.to_i.positive?
          Stock::Apply.call(business: product.business, actor: actor, product_id: product.id,
            change: StockChange.new(kind: "opening", quantity: opening_quantity, operation_key: SecureRandom.uuid))
        end
      end
      true
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, Stock::Apply::Rejected => error
      product.errors.add(:base, error.message) if product.errors.empty?
      false
    end
  end
end

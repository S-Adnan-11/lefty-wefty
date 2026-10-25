class StockChange
  include ActiveModel::Model

  attr_accessor :quantity, :kind, :reason, :operation_key
  validates :kind, inclusion: { in: %w[opening receipt adjustment] }
  validates :operation_key, format: { with: /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i }
  validates :quantity, numericality: { only_integer: true, other_than: 0, greater_than_or_equal_to: -Product::MAX_QUANTITY, less_than_or_equal_to: Product::MAX_QUANTITY }
  validates :reason, length: { maximum: 500 }
  validates :reason, presence: true, if: -> { kind == "adjustment" }
  validate :positive_receipt

  def normalized_reason
    case kind
    when "opening" then "Opening stock"
    when "receipt" then "Stock received"
    else reason.to_s.strip
    end
  end

  private
    def positive_receipt
      if %w[receipt opening].include?(kind) && quantity.to_i <= 0
        errors.add(:quantity, "must be positive for a receipt or opening stock")
      end
    end
end

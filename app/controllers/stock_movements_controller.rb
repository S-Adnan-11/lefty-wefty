class StockMovementsController < ApplicationController
  def create
    @product = Current.business.products.find(params[:product_id])
    @change = StockChange.new(params.expect(stock_change: [ :kind, :quantity, :reason, :operation_key ]))
    # Opening stock is only available as part of product creation.
    raise Stock::Apply::Rejected, "Choose receipt or adjustment" unless %w[receipt adjustment].include?(@change.kind)

    Stock::Apply.call(business: Current.business, actor: Current.user, product_id: @product.id, change: @change)
    redirect_to @product, notice: "Stock change recorded. Retrying this submission will not record it twice.", status: :see_other
  rescue Stock::Apply::Rejected, ActiveRecord::RecordInvalid => error
    @product.reload
    @change.errors.add(:base, error.message) if @change.errors.empty?
    @page = @page_count = 1
    @movements = @product.inventory_logs.includes(:actor).order(id: :desc).limit(20)
    render "products/show", status: :unprocessable_entity
  end
end

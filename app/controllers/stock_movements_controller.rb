class StockMovementsController < ApplicationController
  include Pagination

  def index
    @kind = params[:kind].presence_in(%w[opening receipt adjustment sale sale_void])
    @product_id = params[:product_id].to_s
    scope = Current.business.inventory_logs
    scope = scope.where(kind: @kind) if @kind
    if @product_id.present?
      raise ActiveRecord::RecordNotFound unless /\A[1-9][0-9]{0,18}\z/.match?(@product_id) && @product_id.to_i <= Order::MAX_AMOUNT
      product = Current.business.products.find(@product_id)
      scope = scope.where(product_id: product.id)
    end
    @products = Current.business.products.order(:name, :id)
    @page, @page_count, @movements = paginate(scope.includes(:product, :order_item).order(created_at: :desc, id: :desc))
  end

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
    @movements = @product.inventory_logs.includes(:actor, :order_item).order(id: :desc).limit(20)
    render "products/show", status: :unprocessable_entity
  end
end

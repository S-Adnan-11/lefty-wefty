class ProductsController < ApplicationController
  before_action :set_product, only: %i[show edit update archive]

  def index
    @status = %w[active low archived].include?(params[:status]) ? params[:status] : "active"
    scope = Current.business.products
    scope = case @status
    when "archived" then scope.where.not(archived_at: nil)
    when "low" then scope.low_stock
    else scope.active
    end
    @query = params[:q].to_s.strip.first(160)
    if @query.present?
      pattern = "%#{Product.sanitize_sql_like(@query)}%"
      scope = scope.where("name ILIKE :q OR sku ILIKE :q", q: pattern)
    end
    @page, @page_count, @products = paginate(scope.order(:name, :id))
  end

  def show
    @page, @page_count, @movements = paginate(@product.inventory_logs.includes(:actor).order(id: :desc))
    @change = StockChange.new(kind: "receipt", operation_key: SecureRandom.uuid)
  end

  def new
    @product = Current.business.products.new(low_stock_threshold: 0)
    @opening_quantity = "0"
  end

  def create
    @product = Current.business.products.new(product_params)
    @opening_quantity = params[:opening_quantity].presence || "0"
    if Products::Create.call(product: @product, actor: Current.user, opening_quantity: @opening_quantity)
      redirect_to @product, notice: "Product created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @product.update(product_params)
      redirect_to @product, notice: "Product updated."
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    @product.errors.add(:sku, "has already been taken")
    render :edit, status: :unprocessable_entity
  end

  def archive
    @product.with_lock { @product.update!(archived_at: @product.archived_at || Time.current) }
    redirect_to @product, notice: "Product archived. Its stock and history are preserved.", status: :see_other
  end

  private
    def set_product
      @product = Current.business.products.find(params[:id])
    end

    def product_params
      params.expect(product: [ :name, :sku, :price_minor, :low_stock_threshold ])
    end

    def paginate(scope)
      page_count = [ (scope.count / 20.0).ceil, 1 ].max
      page = params[:page].to_s.to_i.clamp(1, page_count)
      [ page, page_count, scope.limit(20).offset((page - 1) * 20) ]
    end
end

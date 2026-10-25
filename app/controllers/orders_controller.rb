class OrdersController < ApplicationController
  before_action :set_order, only: %i[show edit update destroy confirm void]

  def index
    @status = %w[draft confirmed voided].include?(params[:status]) ? params[:status] : nil
    scope = Current.business.orders
    scope = scope.where(state: @status) if @status
    @page_count = [ (scope.count / 20.0).ceil, 1 ].max
    @page = params[:page].to_s.to_i.clamp(1, @page_count)
    @orders = scope.order(id: :desc).limit(20).offset((@page - 1) * 20)
  end

  def new
    @submission_key = SecureRandom.uuid
    @lines = []
    prepare_form
  end

  def create
    @submission_key = draft_params[:submission_key]
    @lines = submitted_lines
    order = Sales::Draft.call(business: Current.business, actor: Current.user,
      lines: @lines, submission_key: @submission_key)
    redirect_to order, notice: "Saved sale: #{order.state}. Drafts do not reserve stock.", status: :see_other
  rescue Sales::Rejected, ActiveRecord::RecordInvalid => error
    @error = error.message
    prepare_form
    render :new, status: :unprocessable_entity
  end

  def show
    @items = @order.order_items.includes(:product, :inventory_logs).order(:product_id)
  end

  def edit
    unless @order.draft?
      redirect_to @order, alert: "Only drafts can be edited."
      return
    end
    @lines = @order.order_items.order(:product_id).map { |item| { product_id: item.product_id, quantity: item.quantity } }
    @revision = @order.revision
    prepare_form
  end

  def update
    @lines = submitted_lines
    @revision = draft_params[:revision]
    Sales::Draft.call(business: Current.business, actor: Current.user, order_id: @order.id,
      revision: @revision, lines: @lines)
    redirect_to @order, notice: "Draft saved. Review the updated items and total.", status: :see_other
  rescue Sales::ReviewChanged => error
    redirect_to @order, alert: error.message, status: :see_other
  rescue Sales::Rejected, ActiveRecord::RecordInvalid => error
    @error = error.message
    @order.reload
    prepare_form
    render :edit, status: :unprocessable_entity
  end

  def destroy
    Sales::Draft.discard(business: Current.business, actor: Current.user,
      order_id: @order.id, revision: params[:revision])
    redirect_to orders_path, notice: "Draft discarded. Stock is unchanged.", status: :see_other
  rescue Sales::Rejected => error
    redirect_to @order, alert: error.message, status: :see_other
  end

  def confirm
    result = Sales::Confirm.call(business: Current.business, actor: Current.user, order_id: @order.id,
      revision: params[:revision], review_token: params[:review_token])
    redirect_to result, notice: "Recorded sale is #{result.state}.", status: :see_other
  rescue Sales::Rejected, Stock::Apply::Rejected, ActiveRecord::RecordInvalid => error
    show_error(error)
  rescue ActiveRecord::StatementInvalid
    show_error(StandardError.new("The sale could not be recorded. No sale changes were saved. Review the draft and retry."))
  end

  def void
    Sales::Void.call(business: Current.business, actor: Current.user, order_id: @order.id,
      reason: params[:void_reason], acknowledged: params[:acknowledged])
    redirect_to @order, notice: "Recorded sale is voided. Stock was restored once. No money was refunded.", status: :see_other
  rescue Sales::Rejected, Stock::Apply::Rejected, ActiveRecord::RecordInvalid => error
    show_error(error)
  rescue ActiveRecord::StatementInvalid
    show_error(StandardError.new("The void could not be recorded. No void changes were saved. Review the sale and retry."))
  end

  private
    def set_order
      @order = Current.business.orders.find(params[:id])
    end

    def draft_params
      params.expect(order: [ :submission_key, :revision, lines: [ [ :product_id, :quantity ] ] ])
    end

    def submitted_lines
      (draft_params[:lines] || []).map { |line| line.to_h.symbolize_keys }
    end

    def prepare_form
      @products = Current.business.products.active.order(:name, :id)
      @lines = (@lines || []).first(100)
      @lines << { product_id: "", quantity: "" } while @lines.size < 5
    end

    def show_error(error)
      @error = error.message
      @order.reload
      show
      render :show, status: :unprocessable_entity
    end
end

class WorkspaceController < ApplicationController
  def show
    @active_count = Current.business.products.active.count
    @low_stock_count = Current.business.products.low_stock.count
    @total_units = Current.business.products.active.sum(:quantity)
    @low_stock = Current.business.products.low_stock.order(:name, :id).limit(8)
    now = Time.current
    month = now.in_time_zone(Current.business.timezone).strftime("%Y-%m")
    @month_sales = Reports::MonthlySales.call(business: Current.business, actor: Current.user,
      first_month: month, last_month: month, now: now)
    @recent_sales = Current.business.orders.where(state: %w[confirmed voided]).order(confirmed_at: :desc, id: :desc).limit(8)
    @recent_movements = Current.business.inventory_logs.includes(:product, :order_item).order(created_at: :desc, id: :desc).limit(8)
  end
end

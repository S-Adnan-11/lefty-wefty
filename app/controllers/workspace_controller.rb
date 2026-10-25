class WorkspaceController < ApplicationController
  def show
    @active_count = Current.business.products.active.count
    @low_stock_count = Current.business.products.low_stock.count
    @total_units = Current.business.products.active.sum(:quantity)
    @low_stock = Current.business.products.low_stock.order(:name, :id).limit(8)
    @recent_movements = Current.business.inventory_logs.includes(:product).order(id: :desc).limit(8)
  end
end

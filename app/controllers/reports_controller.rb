class ReportsController < ApplicationController
  def show
    current = Time.current.in_time_zone(Current.business.timezone).to_date.beginning_of_month
    @presets = [ [ "This month", current ], [ "Last 3 months", current << 2 ], [ "Last 12 months", current << 11 ] ]
    @first_month = params[:first_month]
    @last_month = params[:last_month]
    @report = Reports::MonthlySales.call(business: Current.business, actor: Current.user,
      first_month: @first_month, last_month: @last_month)
    @first_month = @report.first_month.strftime("%Y-%m")
    @last_month = @report.last_month.strftime("%Y-%m")
  rescue Reports::MonthlySales::InvalidRange => error
    @error = error.message
    render :show, status: :unprocessable_entity
  end
end

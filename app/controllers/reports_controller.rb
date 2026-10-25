class ReportsController < ApplicationController
  def show
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

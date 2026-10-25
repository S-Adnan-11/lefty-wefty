module Pagination
  extend ActiveSupport::Concern
  private
    def paginate(scope)
      page_count = [ (scope.count + 19) / 20, 1 ].max
      raw = params[:page].to_s
      page = /\A[1-9][0-9]{0,8}\z/.match?(raw) ? raw.to_i.clamp(1, page_count) : 1
      [ page, page_count, scope.limit(20).offset((page - 1) * 20) ]
    end
end

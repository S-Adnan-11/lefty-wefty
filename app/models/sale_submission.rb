class SaleSubmission < ApplicationRecord
  belongs_to :business
  belongs_to :order, optional: true
end

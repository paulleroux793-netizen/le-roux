class EstimateLine < ApplicationRecord
  include BillableLine

  belongs_to :estimate
  belongs_to :procedure_code, optional: true
  belongs_to :treatment_item, optional: true
end

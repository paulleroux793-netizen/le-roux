class InvoiceLine < ApplicationRecord
  include BillableLine

  belongs_to :invoice
  belongs_to :procedure_code, optional: true
  belongs_to :treatment_item, optional: true
end

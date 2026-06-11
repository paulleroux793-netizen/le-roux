class AddNappiToBillingLines < ActiveRecord::Migration[8.1]
  # Additive + nullable — safe to run on live with zero downtime. NAPPI codes are needed on
  # claims for dispensed materials/medicines/implants/consumables (schemes reimburse by NAPPI).
  def change
    add_column :invoice_lines, :nappi_code, :string
    add_column :estimate_lines, :nappi_code, :string
    add_column :procedure_codes, :nappi_code, :string
  end
end

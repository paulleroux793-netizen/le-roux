class AddProviderNameToBillingDocs < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices,  :provider_name, :string
    add_column :estimates, :provider_name, :string
  end
end

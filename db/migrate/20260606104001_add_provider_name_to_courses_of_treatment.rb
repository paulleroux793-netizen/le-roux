class AddProviderNameToCoursesOfTreatment < ActiveRecord::Migration[8.1]
  # The treating dentist for this course of treatment, so invoices/estimates
  # generated from it carry the provider (Chalita vs Eliska) into production
  # reporting + the medical-aid claim. Uppercased to match invoice/statement.
  def change
    add_column :courses_of_treatment, :provider_name, :string
  end
end

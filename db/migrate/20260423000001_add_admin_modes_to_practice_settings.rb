class AddAdminModesToPracticeSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :practice_settings, :admin_modes, :jsonb, default: {}
  end
end

class AddAdminInstructionsToPracticeSettings < ActiveRecord::Migration[8.0]
  def change
    add_column :practice_settings, :admin_instructions, :text
  end
end

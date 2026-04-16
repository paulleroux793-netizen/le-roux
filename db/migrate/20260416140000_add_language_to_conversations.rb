class AddLanguageToConversations < ActiveRecord::Migration[8.0]
  def change
    add_column :conversations, :language, :string, limit: 5
  end
end

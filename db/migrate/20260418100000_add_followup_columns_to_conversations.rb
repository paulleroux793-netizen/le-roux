class AddFollowupColumnsToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :follow_up_count, :integer, null: false, default: 0
    add_column :conversations, :follow_up_sent_at, :datetime

    add_index :conversations, :follow_up_sent_at
  end
end

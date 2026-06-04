# Mailbox subfolders (Outlook-style folder tree). Each message/thread remembers
# which IMAP folder it came from; the account caches its folder list for the tree.
class AddFoldersToMail < ActiveRecord::Migration[8.1]
  def change
    add_column :mail_messages, :folder, :string, default: "INBOX", null: false
    add_column :mail_threads,  :folder, :string, default: "INBOX", null: false
    add_column :mail_accounts, :folders, :string, array: true, default: []
    add_index :mail_threads, [ :mail_account_id, :folder ]
  end
end

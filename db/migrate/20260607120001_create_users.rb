class CreateUsers < ActiveRecord::Migration[8.1]
  # Per-user authentication + roles (reception / dentist / admin). Additive: the table
  # sits empty and unused until USER_AUTH_ENABLED=true flips the dashboard from the
  # shared HTTP-basic password to per-user logins. Nothing references it before then.
  def change
    create_table :users do |t|
      t.string   :email,           null: false
      t.string   :password_digest, null: false
      t.string   :name,            null: false
      t.string   :role,            null: false, default: "reception"
      t.boolean  :active,          null: false, default: true
      t.datetime :last_login_at
      t.timestamps
    end
    add_index :users, "lower(email)", unique: true, name: "index_users_on_lower_email"
  end
end

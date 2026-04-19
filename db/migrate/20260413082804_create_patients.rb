class CreatePatients < ActiveRecord::Migration[8.1]
  def change
    create_table :patients do |t|
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :phone, null: false
      t.string :email
      t.date :date_of_birth
      t.text :notes

      t.timestamps
    end

    add_index :patients, :phone, unique: true
    add_index :patients, [ :last_name, :first_name ]
  end
end

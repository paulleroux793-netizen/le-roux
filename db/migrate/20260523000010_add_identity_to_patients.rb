# Adds a flexible identity number to patients (SA ID / passport / DOB+zeros for kids) and makes
# phone OPTIONAL so family members who share one contact number can be imported.
#
# SAFETY: both changes are RELAXATIONS — existing rows already have a phone, and all live code paths
# (WhatsApp booking) always set a phone, so existing behaviour is unchanged. The phone UNIQUE index is
# kept (Postgres allows multiple NULLs), so live `Patient.find_by(phone:)` still resolves uniquely.
class AddIdentityToPatients < ActiveRecord::Migration[8.1]
  def change
    add_column :patients, :id_number, :string
    add_index  :patients, :id_number, where: "id_number IS NOT NULL"
    change_column_null :patients, :phone, true
  end
end

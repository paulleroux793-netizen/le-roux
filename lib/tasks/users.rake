# Manage dashboard users from the CLI (used to seed accounts before/at the auth cutover).
#   bin/rails users:upsert EMAIL=chalita@drchalitaleroux.co.za PASSWORD='...' NAME='Dr Chalita' ROLE=admin
#   bin/rails users:list
#   bin/rails users:deactivate EMAIL=someone@...
namespace :users do
  desc "Create or update a user (EMAIL, PASSWORD, NAME, ROLE=reception|dentist|admin)"
  task upsert: :environment do
    email = ENV.fetch("EMAIL").strip.downcase
    u = User.find_or_initialize_by(email: email)
    u.name     = ENV["NAME"] if ENV["NAME"].present?
    u.role     = ENV["ROLE"] if ENV["ROLE"].present?
    u.password = ENV["PASSWORD"] if ENV["PASSWORD"].present?
    u.active   = true
    u.save!
    puts "saved: #{u.email} (#{u.role})"
  end

  desc "List dashboard users"
  task list: :environment do
    User.order(:role, :email).each do |u|
      puts "#{u.email}\t#{u.role}\t#{u.active ? 'active' : 'disabled'}\tlast_login=#{u.last_login_at}"
    end
    puts "(#{User.count} users)"
  end

  desc "Deactivate a user (EMAIL=)"
  task deactivate: :environment do
    u = User.find_by("lower(email) = ?", ENV.fetch("EMAIL").strip.downcase)
    abort "no such user" unless u
    u.update!(active: false)
    puts "deactivated #{u.email}"
  end
end

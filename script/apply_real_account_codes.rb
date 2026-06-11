# Set Ivory billing accounts to Elixir's REAL codes (ACCOUNTS.INTERNAL, e.g. W0046),
# mapped via each account's PATIENTS → account_cl (robust even if codes were left
# as TMP by a prior partial run). Full-TMP pass then assign with collision-safety.
require "json"
internal = JSON.parse(File.read("tmp/internal.json"))    # account_cl => real code
pdata    = JSON.parse(File.read("tmp/patients.json"))

id_to_cl, name_to_cl = {}, {}
pdata.each do |p|
  cl = p["account_cl"]; next unless cl
  id_to_cl[p["id_number"]] = cl if p["id_number"].present?
  name_to_cl["#{p['first_name']} #{p['last_name']}".downcase.strip] = cl
end

targets = {} # ba.id => real code
BillingAccount.includes(:patients).find_each do |ba|
  cl = nil
  ba.patients.each do |pt|
    cl = id_to_cl[pt.id_number] || name_to_cl["#{pt.first_name} #{pt.last_name}".downcase.strip]
    break if cl
  end
  real = cl && internal[cl]
  targets[ba.id] = real if real.present?
end

# Pass 1: everyone to a unique placeholder.
BillingAccount.find_each { |ba| ba.update_columns(account_code: "TMP#{ba.id}") }
# Pass 2: assign real codes, suffixing on the rare collision.
used = {}; n = 0
targets.each do |id, code|
  c = code; i = 1
  while used[c]; c = "#{code}_#{i}"; i += 1; end
  used[c] = true
  BillingAccount.where(id: id).update_all(account_code: c); n += 1
end
# Accounts with no matched real code: clear (nil sorts last; no TMP noise).
BillingAccount.where("account_code LIKE 'TMP%'").update_all(account_code: nil)

puts "[real-codes] applied #{n} real Elixir codes; #{BillingAccount.where(account_code: nil).count} left without a code"
w = Patient.where("last_name ILIKE ? AND first_name ILIKE ?", "willemse", "carol").first
puts "[real-codes] Carol Willemse -> #{w&.account_code} (expect W0046)"

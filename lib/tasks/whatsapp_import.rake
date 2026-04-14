namespace :whatsapp do
  # Phase 10 — CLI entry-point for historical WhatsApp imports.
  #
  # Examples:
  #   # Preferred — JSON export transformed into our schema:
  #   bin/rails "whatsapp:import[tmp/imports/chats.json]"
  #
  #   # WhatsApp mobile .txt export (single-thread file):
  #   bin/rails "whatsapp:import[tmp/imports/emily.txt,Dr Le Roux,+27831234567]"
  #
  # See WhatsappImportService for the JSON schema and .txt format
  # expectations.
  desc "Import historical WhatsApp chats from a JSON or TXT export"
  task :import, [:path, :owner_name, :patient_phone] => :environment do |_, args|
    path = args[:path]
    abort "Usage: rails 'whatsapp:import[path,owner_name?,patient_phone?]'" if path.blank?

    puts "Importing #{path}…"
    result = WhatsappImportService.import_file(
      path,
      owner_name:    args[:owner_name],
      patient_phone: args[:patient_phone]
    )

    puts "  created: #{result.created}"
    puts "  updated: #{result.updated}"
    puts "  skipped: #{result.skipped}"
    if result.errors.any?
      puts "  errors:"
      result.errors.each { |e| puts "    - #{e}" }
    end
  end
end

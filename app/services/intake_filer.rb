# Saves the completed intake pack as a PDF into the practice's "1. Patient Files"
# OneDrive folder, named "First Last YYYY-MM-DD.pdf" (completion date), so reception
# has the file ready to print + add to the patient's physical file on arrival.
#
# The folder is bind-mounted into the container at INTAKE_FILE_DIR (see
# docker-compose.yml). If the mount/env is absent (e.g. in test), this is a no-op —
# the email copy still goes out, so a missing mount never blocks a submission.
class IntakeFiler
  def self.call(patient)
    new(patient).call
  end

  def initialize(patient)
    @patient = patient
  end

  def call
    dir = ENV["INTAKE_FILE_DIR"].presence
    return nil unless dir && File.directory?(dir)

    path = File.join(dir, filename)
    File.binwrite(path, IntakePdf.new(@patient).render)
    Rails.logger.info("[IntakeFiler] saved #{path}")
    path
  rescue StandardError => e
    Rails.logger.error("[IntakeFiler] failed to save patient file: #{e.message}")
    nil
  end

  private

  # "First Last YYYY-MM-DD.pdf" — stripped of characters Windows/OneDrive dislike.
  def filename
    base = "#{@patient.first_name} #{@patient.last_name} #{Date.current.strftime('%Y-%m-%d')}"
    safe = base.gsub(/[\\\/:*?"<>|]/, " ").squeeze(" ").strip
    "#{safe}.pdf"
  end
end

# POPIA s23 — Data Subject Access Request (DSAR). Compiles EVERYTHING Ivory holds
# on one patient into a single JSON export the practice can hand to the patient on
# request. Read-only; behind the dashboard auth (staff initiate it on the patient's
# behalf). Encrypted PHI is decrypted in the export — it is the data subject's own
# data, which is the point of an access request.
#
# Deliberately NOT a deletion endpoint: POPIA erasure must be a careful, audited,
# human-confirmed action (it cascades across clinical/billing records and has legal
# retention exceptions), so it is handled as a supervised flow, never a one-click route.
class DataExportsController < ApplicationController
  def show
    patient = Patient.find(params[:patient_id])

    export = {
      exported_at:    Time.current.iso8601,
      generated_by:   audit_performer,
      data_subject:   patient.as_json,
      related_records: {}
    }

    # Walk the patient's owned records generically so the export stays complete as
    # the schema grows (no hand-maintained list to fall out of date). Shallow JSON
    # only — we export THIS patient's data, not nested third parties.
    patient.class.reflect_on_all_associations(:has_many).each do |assoc|
      next if assoc.options[:through]
      export[:related_records][assoc.name] = safe_dump(patient, assoc.name)
    end
    patient.class.reflect_on_all_associations(:has_one).each do |assoc|
      next if assoc.options[:through]
      export[:related_records][assoc.name] = safe_dump(patient, assoc.name)
    end

    if defined?(AuditService)
      AuditService.log(action: "data_export", summary: "POPIA data export for patient ##{patient.id}",
                       resource: patient, performed_by: audit_performer)
    end

    send_data JSON.pretty_generate(export),
      filename: "ivory-data-export-patient-#{patient.id}-#{Date.current.iso8601}.json",
      type: "application/json", disposition: "attachment"
  end

  private

  def safe_dump(patient, assoc_name)
    rel = patient.public_send(assoc_name)
    rel.respond_to?(:to_a) ? rel.as_json : rel&.as_json
  rescue StandardError => e
    { error: e.class.name }
  end
end

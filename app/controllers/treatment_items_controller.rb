# Treatment items — staff status transitions and edits.
# R1.1 — the clinical→billing bridge needs a way to flip planned → completed
# (and mistakes → voided). Until this existed, billing could only be done
# via the rails console.
class TreatmentItemsController < ApplicationController
  ALLOWED_STATUSES = %w[planned completed failed voided].freeze

  # PATCH /treatment_items/:id
  #
  # Supported params:
  #   - status: one of planned / completed / failed / voided
  #   - tooth_number, surface, fee_cents — optional small edits
  #
  # When transitioning to "completed" we stamp completed_date = today
  # (the model's #complete! also does this, but we set it here so any
  # cycling back through planned re-stamps correctly).
  def update
    item = TreatmentItem.find(params[:id])
    new_status = params[:status].to_s

    if new_status.present? && !ALLOWED_STATUSES.include?(new_status)
      return redirect_back fallback_location: course_of_treatment_path(item.course_of_treatment_id),
        alert: "Unknown status: #{new_status}", status: :see_other
    end

    attrs = {}
    attrs[:status] = new_status if new_status.present?
    attrs[:completed_date] = Date.current if new_status == "completed"
    attrs[:completed_date] = nil          if new_status == "planned"  # revert
    attrs[:tooth_number] = params[:tooth_number] if params.key?(:tooth_number)
    attrs[:surface]      = params[:surface]      if params.key?(:surface)
    if params[:fee].present?
      attrs[:fee_cents] = (params[:fee].to_f * 100).round
    end

    item.update!(attrs)

    AuditService.log(
      action: "treatment_item.#{new_status.presence || 'updated'}",
      summary: "#{new_status&.humanize.presence || 'Updated'} item " \
               "#{item.procedure_code&.code} on COT ##{item.course_of_treatment_id}",
      resource: item,
      details: attrs.transform_values(&:to_s),
      performed_by: audit_performer,
      ip_address: request.remote_ip
    )

    expire_dev_page_cache("courses-of-treatment")

    notice = case new_status
             when "completed" then "Marked done"
             when "voided"    then "Voided"
             when "failed"    then "Marked failed"
             when "planned"   then "Reverted to planned"
             else "Updated"
             end

    redirect_back fallback_location: course_of_treatment_path(item.course_of_treatment_id),
      notice: notice, status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: courses_of_treatment_path,
      alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end
end

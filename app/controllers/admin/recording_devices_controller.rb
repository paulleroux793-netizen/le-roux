# N1 — Admin-only management of physical recording devices.
# Paul sees this; receptionists / dentists never need to. The
# devices show up automatically as the listener daemon registers them
# (future), but for now they can be edited by hand here.
#
# Route: /admin/recording_devices (index + create + update + delete)
class Admin::RecordingDevicesController < ApplicationController
  def index
    devices = RecordingDevice.order(:location, :name).to_a
    render inertia: "Admin/RecordingDevices", props: {
      devices: devices.map { |d|
        {
          id: d.id, name: d.name, location: d.location,
          enabled: d.enabled, last_seen_at: d.last_seen_at&.iso8601,
          notes: d.notes,
          session_count_today: ScribeSession.where(recording_device_id: d.id)
                                            .where("created_at >= ?", Time.current.beginning_of_day).count
        }
      },
      locations: RecordingDevice::LOCATIONS
    }
  end

  def create
    rd = RecordingDevice.create!(device_params.merge(enabled: true))
    AuditService.log(action: "recording_device.created", summary: "Added recording device #{rd.name}",
                     resource: rd, performed_by: audit_performer, ip_address: request.remote_ip)
    redirect_to admin_recording_devices_path, notice: "Device #{rd.name} added", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: admin_recording_devices_path,
      alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  def update
    rd = RecordingDevice.find(params[:id])
    rd.update!(device_params)
    AuditService.log(action: "recording_device.updated", summary: "Updated recording device #{rd.name}",
                     resource: rd, details: device_params.to_h,
                     performed_by: audit_performer, ip_address: request.remote_ip)
    redirect_to admin_recording_devices_path, notice: "Updated #{rd.name}", status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: admin_recording_devices_path,
      alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  def destroy
    rd = RecordingDevice.find(params[:id])
    rd.destroy!
    AuditService.log(action: "recording_device.deleted", summary: "Removed recording device #{rd.name}",
                     details: { name: rd.name, location: rd.location },
                     performed_by: audit_performer, ip_address: request.remote_ip)
    redirect_to admin_recording_devices_path, notice: "Removed #{rd.name}", status: :see_other
  end

  private

  def device_params
    params.require(:recording_device).permit(:name, :location, :enabled, :notes)
  end
end

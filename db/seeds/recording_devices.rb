# N1 — seed the default 2-mic layout: one in the surgery, one at
# reception. The admin (Paul) can rename + add more from
# /admin/recording_devices. Idempotent: re-running skips existing rows.
created = 0
RecordingDevice::DEFAULT_LAYOUT.each do |attrs|
  rd = RecordingDevice.find_or_initialize_by(name: attrs[:name])
  next unless rd.new_record?
  rd.assign_attributes(attrs.merge(enabled: true))
  rd.save!
  created += 1
end
puts "recording_devices: #{created} created (#{RecordingDevice.count} total)"

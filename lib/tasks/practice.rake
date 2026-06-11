namespace :practice do
  # SINGLE SOURCE OF TRUTH for working hours.
  #
  # The AI quotes hours from config/practice_config.yml (working_hours:), but the
  # booking ENGINE enforces hours via the per-provider DoctorSchedule table. This
  # task pushes the YAML hours into every active provider's DoctorSchedule so the
  # two can never drift — the YAML is authoritative. Idempotent: if the DB already
  # matches the YAML it writes nothing. Run it after editing working_hours in the
  # YAML (it is also run automatically on every rig deploy).
  #
  #   bin/rails practice:sync_schedules
  desc "Sync working_hours from practice_config.yml into per-provider DoctorSchedule (YAML is the source of truth)"
  task sync_schedules: :environment do
    day_map = { monday: 1, tuesday: 2, wednesday: 3, thursday: 4, friday: 5, saturday: 6, sunday: 0 }
    hours = PracticeConfig.working_hours || {}
    updated = 0
    providers = Provider.active.to_a

    providers.each do |provider|
      day_map.each do |day_name, wday|
        cfg  = hours[day_name] || {}
        open = cfg[:open] != false && cfg[:start].present?
        sched = DoctorSchedule.find_or_initialize_by(provider_id: provider.id, day_of_week: wday)
        sched.active     = open
        sched.start_time = open ? cfg[:start] : nil
        sched.end_time   = open ? cfg[:end]   : nil
        # No lunch break in this practice — keep breaks nil unless the YAML adds them later.
        if sched.changed?
          sched.save!
          updated += 1
        end
      end
    end

    puts "practice:sync_schedules — #{providers.size} active provider(s); #{updated} DoctorSchedule row(s) updated from the YAML."
  end
end

class SendAppointmentConfirmationJob < ApplicationJob
  queue_as :default

  def perform(appointment_id)
    appointment = Appointment.includes(:patient).find(appointment_id)
    AppointmentConfirmationSender.new(appointment).send
  end
end

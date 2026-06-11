class AddBookingControlsToProviders < ActiveRecord::Migration[8.1]
  # Lets a provider be temporarily closed for NEW bookings (e.g. Dr Chalita on
  # maternity leave) while their existing diary + column stay visible. New AI and
  # default bookings route to the first `bookable` provider; the diary greys the
  # column and blocks click-to-book up to `unavailable_until`.
  def change
    add_column :providers, :accepting_bookings, :boolean, default: true, null: false
    add_column :providers, :unavailable_until, :date
  end
end

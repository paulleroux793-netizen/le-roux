# Read-only view of treatment macros and how each expands into procedure lines.
# Additive — new route.
class TreatmentMacrosController < ApplicationController
  def index
    macros = TreatmentMacro.includes(treatment_macro_items: :procedure_code).order(:access_code).to_a
    render inertia: "TreatmentMacros", props: {
      macros: macros.map { |m| macro_props(m) },
      stats: { total: macros.size, lines: TreatmentMacroItem.count }
    }
  end

  private

  def macro_props(m)
    items = m.treatment_macro_items.map do |i|
      fee_cents = i.procedure_code&.default_fee_cents.to_i
      {
        tariff_code: i.tariff_code,
        description: i.procedure_code&.description || i.more_info,
        quantity: i.quantity,
        line_total: i.quantity * (fee_cents / 100.0)
      }
    end
    {
      id: m.id,
      access_code: m.access_code,
      name: m.name,
      laboratory: m.laboratory,
      line_count: items.size,
      estimated_total: items.sum { |i| i[:line_total] }.round(2),
      items: items
    }
  end
end

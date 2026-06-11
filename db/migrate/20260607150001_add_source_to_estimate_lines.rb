# Tag how each estimate line was created so we can measure the AI composer's quality:
# 'manual' (typed / quick-add / macro) vs 'ai' (auto-populated by compose_treatment_lines).
# Comparing how many 'ai' lines survive to acceptance vs get removed = the edit/override rate,
# the key feedback signal for improving the composer. Additive + reversible (default 'manual').
class AddSourceToEstimateLines < ActiveRecord::Migration[8.1]
  def change
    add_column :estimate_lines, :source, :string, default: "manual", null: false
  end
end

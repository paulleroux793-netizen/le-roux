# Persist the AI composer's guidance note (e.g. "assumed 3 surfaces — confirm with the dentist",
# "premolar may have a 2nd canal") so reception/dentist see what to verify on the estimate, not
# just a one-shot flash at compose time. Separate from `notes` (which holds [elixir]/[invoice] tags).
class AddAiNoteToEstimates < ActiveRecord::Migration[8.1]
  def change
    add_column :estimates, :ai_note, :text
  end
end

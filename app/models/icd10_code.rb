# Dental ICD-10 diagnosis code reference. Seeded from the standard SA dental coding set
# (K00-K14 oral cavity + Z01.20 routine exam + common trauma codes). Used as a picker on
# treatment items / invoice lines so each procedure carries the clinical reason.
class Icd10Code < ApplicationRecord
  validates :code, presence: true, uniqueness: true
  validates :description, presence: true

  scope :active, -> { where(active: true) }
  scope :for_category, ->(c) { where(category: c) }

  # Heuristic mapping from a tooth-chart condition to the most likely ICD-10 code.
  # Used by the clickable odontogram (next chunk) to suggest a default diagnosis.
  CONDITION_DEFAULT = {
    "caries"             => "K02.9",
    "filling"            => "K02.9",
    "crown"              => "K02.5",
    "bridge"             => "K08.1",
    "root_canal"         => "K04.0",
    "missing"            => "K08.1",
    "extraction_planned" => "K04.7",
    "fracture"           => "S02.5",
    "implant"            => "K08.1"
  }.freeze
end

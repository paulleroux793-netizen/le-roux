# A SIDEXIS imaging study (X-ray / panoramic / CBCT 3D / clinical photo) linked to a patient.
# Originals stay on-prem; this is the metadata + match status. (Ivory, Phase 5.)
class ImagingStudy < ApplicationRecord
  MODALITIES = %w[intraoral_2d panoramic cephalometric cbct_3d photo other].freeze
  MODALITY_LABELS = {
    "intraoral_2d" => "Intraoral X-ray", "panoramic" => "Panoramic (OPG)",
    "cephalometric" => "Cephalometric", "cbct_3d" => "CBCT 3D", "photo" => "Clinical photo", "other" => "Other"
  }.freeze
  STATUSES = %w[needs_match matched ignored].freeze

  belongs_to :patient, optional: true

  validates :modality, inclusion: { in: MODALITIES }
  validates :status, inclusion: { in: STATUSES }

  scope :needs_match, -> { where(status: "needs_match") }
  scope :matched, -> { where(status: "matched") }

  def modality_label = MODALITY_LABELS[modality] || modality
end

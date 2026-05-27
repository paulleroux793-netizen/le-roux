require "rails_helper"

RSpec.describe ElixirMirror::DiaryParser do
  # Real Elixir-exported diary PDF from Dr Chalita's practice (read-only).
  # If the file isn't accessible (different machine / CI), these specs skip
  # rather than fail — they're integration-style probes against real data.
  let(:diary_path) do
    "/d/Paul le Roux/OneDrive/1. Dr Chalita le Roux/3. Diary/8 MAY 2026.pdf"
  end

  before do
    skip "Elixir diary PDF not present at #{diary_path}" unless File.exist?(diary_path)
  end

  describe "#parse_header" do
    it "extracts the dentist and appointment date from the resource line" do
      header = described_class.new(diary_path).parse_header
      expect(header[:dentist]).to match(/DR\s+ELISKA\s+ROBINSON/i)
      expect(header[:appointment_date]).to eq(Date.new(2026, 5, 8))
    end
  end

  describe "#parse" do
    let(:rows) { described_class.new(diary_path).parse }

    it "returns one hash per appointment slot (excludes 'Closed' rows)" do
      expect(rows).to be_a(Array)
      expect(rows.size).to be > 0
      rows.each { |r| expect(r[:start_at]).not_to be_nil }
    end

    it "captures patient name + account code for existing patients" do
      michelle = rows.find { |r| r[:patient_name]&.match?(/MICHELLE ELS/i) }
      expect(michelle).not_to be_nil
      expect(michelle[:account_code]).to eq("E0011")
      expect(michelle[:is_new_patient]).to be false
      expect(michelle[:reason]).to match(/FILLINGS/i)
    end

    it "marks [New patient] rows correctly" do
      new_patient_row = rows.find { |r| r[:is_new_patient] }
      expect(new_patient_row).not_to be_nil
      expect(new_patient_row[:account_code]).to be_nil
    end

    it "parses the due-amount and cellular when present" do
      with_cell = rows.find { |r| r[:cellular].present? }
      expect(with_cell).not_to be_nil
      expect(with_cell[:cellular]).to match(/^0\d{6,10}$/)
    end
  end
end

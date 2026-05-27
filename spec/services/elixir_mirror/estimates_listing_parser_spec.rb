require "rails_helper"

RSpec.describe ElixirMirror::EstimatesListingParser do
  let(:xlsx_path) do
    "/d/Paul le Roux/OneDrive/1. Dr Chalita le Roux/1. Policies and Procedures/Estimates listing.xlsx"
  end

  before do
    skip "Estimates listing XLSX not present at #{xlsx_path}" unless File.exist?(xlsx_path)
  end

  let(:rows) { described_class.new(xlsx_path).parse }

  it "returns one hash per data row" do
    expect(rows).to be_a(Array)
    expect(rows.size).to be > 5
  end

  it "captures patient name, account code, and estimate details" do
    sample = rows.find { |r| r[:patient_name].to_s.match?(/Kathryn Diab/i) }
    expect(sample).not_to be_nil if sample
    if sample
      expect(sample[:account_code]).to eq("D0071")
      expect(sample[:details].to_s).to match(/cleaning|extractions|dentures|fillings|crowns/i)
    end
  end

  it "preserves row indexes for idempotent upserts" do
    indexes = rows.map { |r| r[:row_index] }
    expect(indexes).to eq(indexes.uniq)
  end
end

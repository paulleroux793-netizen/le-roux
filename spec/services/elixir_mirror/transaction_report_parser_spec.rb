require "rails_helper"

RSpec.describe ElixirMirror::TransactionReportParser do
  let(:txn_path) do
    "/d/Paul le Roux/OneDrive/1. Dr Chalita le Roux/4. Transaction report/8 MAY 2026.pdf"
  end

  before do
    skip "Elixir transaction PDF not present at #{txn_path}" unless File.exist?(txn_path)
  end

  let(:rows) { described_class.new(txn_path).parse }

  it "returns one row per procedure / payment line" do
    expect(rows).to be_a(Array)
    expect(rows.size).to be > 10
  end

  it "captures the date, account, procedure code, and debit for a known line" do
    michelle_line = rows.find { |r| r[:account_code] == "E0011" && r[:procedure_code] == "8369" }
    expect(michelle_line).not_to be_nil
    expect(michelle_line[:transaction_date]).to eq(Date.new(2026, 5, 8))
    expect(michelle_line[:tooth]).to eq("17")
    expect(michelle_line[:debit]).to eq(BigDecimal("1251.66"))
    expect(michelle_line[:dentist]).to match(/ELISKA/i)
  end

  it "captures lab item codes (B01 / C26)" do
    bridge = rows.find { |r| r[:procedure_code] == "B01" }
    expect(bridge).not_to be_nil
    expect(bridge[:debit]).to be > 0

    crown = rows.find { |r| r[:procedure_code] == "C26" }
    expect(crown).not_to be_nil
    expect(crown[:debit]).to be > 0
  end

  it "captures P-CARD payment rows with credit set to a positive magnitude" do
    payment = rows.find { |r| r[:procedure_code] == "P-CARD" && r[:account_code] == "E0011" }
    expect(payment).not_to be_nil
    expect(payment[:credit]).to be > 0
    expect(payment[:debit]).to eq(BigDecimal(0))
  end

  it "totals (procedures debit - payments credit) close to zero per Elixir day-total invariant" do
    procedure_total = rows.reject { |r| %w[P-CARD P-CASH P-EFT].include?(r[:procedure_code]) }.sum { |r| r[:debit] }
    payment_total   = rows.select { |r| %w[P-CARD P-CASH P-EFT].include?(r[:procedure_code]) }.sum { |r| r[:credit] }
    # Allow a small unallocated payment delta (Elixir's "Unallocated payments" field)
    expect((procedure_total - payment_total).abs).to be < 10000
  end
end

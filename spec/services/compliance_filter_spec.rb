require "rails_helper"

RSpec.describe ComplianceFilter do
  describe ".scrub" do
    def scrub(text)
      described_class.scrub(text)
    end

    context "with compliant text" do
      it "returns the text unchanged and flags nothing" do
        text = "Your appointment is booked for Tuesday, 9 June at 10:00. See you then!"
        result = scrub(text)
        expect(result[:text]).to eq(text)
        expect(result[:flagged]).to be_empty
      end

      it "handles blank input safely" do
        expect(scrub(nil)).to eq(text: nil, flagged: [])
        expect(scrub("")).to eq(text: "", flagged: [])
      end
    end

    context "Rule 3 — after-hours / 24-hour / weekend / see-you-today" do
      it "softens 'we'll see you today'" do
        result = scrub("Pop in and we'll see you today.")
        expect(result[:flagged]).to include(:after_hours)
        expect(result[:text]).not_to match(/see you today/i)
        expect(result[:text]).to match(/as quickly as possible once you arrive/i)
      end

      it "rewrites a bare 'see you today'" do
        result = scrub("Great, see you today!")
        expect(result[:flagged]).to include(:after_hours)
        expect(result[:text]).not_to match(/see you today/i)
      end

      it "replaces 24-hour framing with real hours" do
        result = scrub("We are open 24 hours for emergencies.")
        expect(result[:flagged]).to include(:after_hours)
        expect(result[:text]).to match(/Monday to Friday, 8am–5pm/i)
        expect(result[:text]).not_to match(/24[\s\/-]?hour/i)
      end

      it "rewrites weekend availability claims" do
        result = scrub("We offer weekend appointments too.")
        expect(result[:flagged]).to include(:after_hours)
        expect(result[:text]).to match(/closed on weekends/i)
      end
    end

    context "Rule 4 — direct medical-aid billing" do
      it "rewrites 'we bill your medical aid for you'" do
        result = scrub("Don't worry, we bill your medical aid for you.")
        expect(result[:flagged]).to include(:medical_aid_direct)
        expect(result[:text]).to match(/you submit to your medical scheme/i)
        expect(result[:text]).not_to match(/we bill your medical aid/i)
      end

      it "rewrites 'we submit your claims on your behalf'" do
        result = scrub("We submit your claims on your behalf.")
        expect(result[:flagged]).to include(:medical_aid_direct)
        expect(result[:text]).not_to match(/we submit your claims/i)
      end
    end

    context "Rule 5 — medication dosing" do
      it "strips an explicit mg + frequency dose" do
        result = scrub("Take 400 mg ibuprofen every 6 hours for the pain.")
        expect(result[:flagged]).to include(:medication_dosing)
        expect(result[:text]).not_to match(/400\s?mg/i)
        expect(result[:text]).to match(/medication packaging/i)
      end

      it "strips a 'two tablets every 4 hours' instruction" do
        result = scrub("You can take two tablets every 4 hours.")
        expect(result[:flagged]).to include(:medication_dosing)
        expect(result[:text]).to match(/medication packaging/i)
      end
    end

    context "Rule 6 — superlatives / absolute claims / guarantees" do
      it "replaces 'painless'" do
        result = scrub("Our whitening is completely painless.")
        expect(result[:flagged]).to include(:superlatives)
        expect(result[:text]).not_to match(/painless/i)
      end

      it "replaces 'guaranteed'" do
        result = scrub("Results are guaranteed.")
        expect(result[:flagged]).to include(:superlatives)
        expect(result[:text]).not_to match(/guarantee/i)
      end

      it "replaces 'the best'" do
        result = scrub("We are the best dentist in town.")
        expect(result[:flagged]).to include(:superlatives)
        expect(result[:text]).to match(/a trusted/i)
      end
    end

    context "Rule 8 — Pretoria geo" do
      it "rewrites a standalone Pretoria reference to Roodepoort" do
        result = scrub("Our practice is in Pretoria.")
        expect(result[:flagged]).to include(:geo_pretoria)
        expect(result[:text]).to match(/in Roodepoort/i)
        expect(result[:text]).not_to match(/Pretoria/)
      end

      it "does NOT match Pretoria embedded inside another word (word boundary)" do
        text = "Pretoriastraat is fine to mention."
        result = scrub(text)
        expect(result[:flagged]).not_to include(:geo_pretoria)
        expect(result[:text]).to eq(text)
      end
    end

    context "multiple violations in one message" do
      it "flags and rewrites each rule that fires" do
        result = scrub("We are the best and we bill your medical aid for you, open 24 hours in Pretoria.")
        expect(result[:flagged]).to include(:superlatives, :medical_aid_direct, :after_hours, :geo_pretoria)
        expect(result[:text]).not_to match(/\bthe best\b/i)
        expect(result[:text]).not_to match(/Pretoria/)
        expect(result[:text]).not_to match(/we bill your medical aid/i)
      end
    end
  end
end

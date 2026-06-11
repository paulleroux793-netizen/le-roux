# ReceiptPdf — a payment receipt (acknowledges a Payment), mirroring the invoice
# styling. Header → patient/account → payment details (method/amount/ref/date) →
# what it was applied to + the resulting balance → thank-you. Pure Prawn.
require "prawn"
require "prawn/table"

class ReceiptPdf
  GOLD = "9A7521"

  def self.render(payment)
    new(payment).render
  end

  def initialize(payment)
    @pay = payment
    @practice = PracticeBillingProfile.current
    @account = payment.billing_account
    @patient = payment.patient
    @invoice = payment.invoice
  end

  def render
    @pdf = Prawn::Document.new(page_size: "A4", margin: [ 40, 40, 40, 40 ])
    header
    party_block
    details
    footer
    @pdf.render
  end

  private

  def money(c) = "R#{format('%.2f', c.to_i / 100.0)}"

  # See DocumentPdf#winansi — keep the built-in (Windows-1252) PDF font from
  # 500-ing on names/text outside it (emoji, ā, Greek, Cyrillic): keep Latin-1,
  # transliterate the rest to ASCII, drop the unmappable.
  def winansi(str)
    s = str.to_s
    return s if s.ascii_only?

    s.each_char.map do |ch|
      ch.encode("Windows-1252")
      ch
    rescue Encoding::UndefinedConversionError
      I18n.transliterate(ch, replacement: "")
    end.join
  end

  def header
    @pdf.font_size(18) { @pdf.fill_color GOLD; @pdf.text winansi(@practice.practice_name.to_s), style: :bold; @pdf.fill_color "000000" }
    @pdf.font_size 9
    @pdf.text winansi(@practice.address.to_s) if @practice.address.present?
    @pdf.text "#{@practice.phone} · #{@practice.email}", style: :italic if @practice.phone.present?
    @pdf.text "VAT: #{@practice.vat_number.presence || 'Not registered'}"
    @pdf.move_down 6; @pdf.stroke_color "DDDDDD"; @pdf.stroke_horizontal_rule; @pdf.move_down 10
    @pdf.font_size(14) { @pdf.fill_color GOLD; @pdf.text "RECEIPT", style: :bold, align: :right; @pdf.fill_color "000000" }
    @pdf.font_size 9
    @pdf.text "Receipt no: RCT-#{@pay.id}", align: :right
    @pdf.text "Date: #{@pay.received_at.strftime('%-d %b %Y')}", align: :right
    @pdf.move_down 14
  end

  def party_block
    rows = [
      [ "Received from", winansi(@patient&.full_name.presence || @account&.billing_name.to_s) ],
      [ "Account",       @account&.account_code.to_s ],
    ]
    @pdf.table(rows, cell_style: { borders: [], padding: [ 2, 6, 2, 0 ], size: 10 }) { column(0).font_style = :bold; column(0).text_color = "707070"; column(0).width = 100 }
    @pdf.move_down 14
  end

  def details
    @pdf.font_size 10
    rows = [
      [ "Payment method", @pay.method.to_s.upcase ],
      [ "Amount received", money(@pay.amount_cents) ],
    ]
    rows << [ "Reference", winansi(@pay.reference) ] if @pay.reference.present?
    if @invoice
      rows << [ "Applied to invoice", @invoice.invoice_number ]
      rows << [ "Invoice balance after", money(@invoice.total_cents.to_i - @invoice.paid_cents.to_i) ]
    end
    @pdf.table(rows, width: 340, cell_style: { borders: [ :bottom ], border_color: "EEEEEE", padding: [ 5, 6, 5, 6 ], size: 10 }) do
      column(0).font_style = :bold; column(0).text_color = "707070"; column(0).width = 170
      row(1).background_color = "F5F0E5"; row(1).font_style = :bold
    end
    @pdf.move_down 16
  end

  def footer
    @pdf.stroke_color "DDDDDD"; @pdf.stroke_horizontal_rule; @pdf.move_down 8
    @pdf.font_size(9) { @pdf.fill_color GOLD; @pdf.text "RECEIVED WITH THANKS", style: :bold; @pdf.fill_color "707070" }
    @pdf.font_size 8
    @pdf.text "This receipt acknowledges the payment above. Keep it for your records; submit the related invoice to your medical scheme to claim back."
    @pdf.move_down 8
    @pdf.text "Generated #{Time.current.strftime('%-d %b %Y at %H:%M')}", size: 7, color: "AAAAAA"
  end
end

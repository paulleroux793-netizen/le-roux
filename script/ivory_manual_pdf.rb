# Renders system/memory/IVORY_MANUAL.md into a clean A4 PDF via Prawn.
# Usage (on the rig):  bin/rails runner script/ivory_manual_pdf.rb
# Output: /tmp/IVORY_MANUAL.pdf
require "prawn"

GOLD = "9A7521"
SRC  = Rails.root.join("system/memory/IVORY_MANUAL.md")
OUT  = "/tmp/IVORY_MANUAL.pdf"

# Keep the built-in (Windows-1252) font from crashing on stray unicode (arrows, etc.).
def winansi(str)
  s = str.to_s
  return s if s.ascii_only?
  s.each_char.map do |ch|
    ch.encode("Windows-1252"); ch
  rescue Encoding::UndefinedConversionError
    repl = { "→" => "->", "←" => "<-", "—" => "-", "–" => "-",
             "…" => "...", "→".dup => "->" }
    repl[ch] || I18n.transliterate(ch, replacement: "")
  end.join
end

# Escape for Prawn inline_format, then turn **bold** into <b>.
def inline(str)
  esc = winansi(str).gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
  esc.gsub(/\*\*(.+?)\*\*/) { "<b>#{$1}</b>" }
end

lines = File.read(SRC).split("\n")

pdf = Prawn::Document.new(page_size: "A4", margin: [ 48, 50, 54, 50 ])
pdf.font "Helvetica"

# Footer with page numbers + practice line.
pdf.repeat(:all) do
  pdf.bounding_box([ 0, 24 ], width: pdf.bounds.width, height: 18) do
    pdf.font_size(7) { pdf.fill_color "999999"
      pdf.text "Ivory — Dr Chalita le Roux Inc · System Manual", align: :left, valign: :bottom }
  end
  pdf.fill_color "000000"
end
pdf.number_pages "<page> / <total>", at: [ pdf.bounds.right - 60, 8 ], size: 7, color: "999999"

first_h1 = true
lines.each do |raw|
  line = raw.rstrip
  if line.start_with?("# ")
    pdf.start_new_page unless first_h1
    first_h1 = false
    pdf.move_down 4
    pdf.fill_color GOLD
    pdf.font_size(22) { pdf.text inline(line[2..]), style: :bold, inline_format: true }
    pdf.fill_color "000000"
    pdf.stroke_color "DDDDDD"; pdf.stroke_horizontal_rule; pdf.stroke_color "000000"
    pdf.move_down 10
  elsif line.start_with?("## ")
    pdf.move_down 10
    pdf.fill_color GOLD
    pdf.font_size(14) { pdf.text inline(line[3..]), style: :bold, inline_format: true }
    pdf.fill_color "000000"
    pdf.move_down 4
  elsif line.start_with?("### ")
    pdf.move_down 6
    pdf.font_size(11) { pdf.text inline(line[4..]), style: :bold, inline_format: true }
    pdf.move_down 2
  elsif line.start_with?("- ")
    pdf.font_size(10) do
      pdf.indent(14) { pdf.text "•  " + inline(line[2..]), inline_format: true, leading: 2 }
    end
  elsif line =~ /\A(\d+)\.\s+(.*)\z/
    pdf.font_size(10) do
      pdf.indent(14) { pdf.text "#{$1}.  " + inline($2), inline_format: true, leading: 2 }
    end
  elsif line.strip.empty?
    pdf.move_down 5
  else
    pdf.font_size(10) { pdf.text inline(line), inline_format: true, leading: 2.5, align: :justify }
  end
end

File.binwrite(OUT, pdf.render)
puts "WROTE #{OUT} (#{File.size(OUT)} bytes, #{pdf.page_count} pages)"

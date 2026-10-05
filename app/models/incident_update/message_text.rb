# Update text is markdown. A bullet glyph copied from chat becomes a list item, so every surface draws a list.
module IncidentUpdate::MessageText
  LINE_BULLET = /\A([ \t]*)[•●▪◦‣][ \t]+/
  # Only a glyph that follows the end of a sentence, so "Checkout • Payments" stays one line.
  INLINE_BULLET = /([.:!?])[ \t]+•[ \t]+/
  FENCE = /\A[ \t]*(```|~~~)/

  def self.normalize(text)
    return text if text.blank?

    in_code = false
    text.gsub(/\r\n?/, "\n").split("\n", -1).map do |line|
      if line.match?(FENCE)
        in_code = !in_code
        next line
      end
      next line if in_code

      line.sub(LINE_BULLET, "\\1- ").gsub(INLINE_BULLET, "\\1\n- ")
    end.join("\n")
  end
end

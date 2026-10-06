# How memory text is compared and searched. Memory text is encrypted, so both happen in Ruby over one workspace's
# memories, never in SQL, and nothing derived from the text is stored.
module Chat::Memory::Words
  # Words that only hold a sentence together. Never a negation or a word of order, since "uses" and "does not use",
  # or "before a deploy" and "after a deploy", are different facts.
  FILLER = %w[
    a an the is are was were be been being am of in on at to for from by with and or that which this these those it its
    there here as do does did has have had will would can could should may might shall
  ].to_set.freeze
  # A search also skips words that say little about what is wanted.
  STOP_WORDS = (FILLER + %w[
    about all also any because both but each how i if into just me more most my now other our same so some such than
    their them then they through too very we what when where who whom why you your
  ]).freeze
  # Keeps names such as firefight-prod or db.internal whole.
  TOKEN = /[[:alnum:]]+(?:[-_.][[:alnum:]]+)*/
  # A whole query found as written counts this many times over.
  PHRASE_WEIGHT = 3

  # The words that carry meaning, each cut to its stem, so "restarts" and "restarting" are one word.
  def self.stems(text, skip: STOP_WORDS)
    text.to_s.downcase.scan(TOKEN).reject { |word| skip.include?(word) }.map { |word| stem(word) }
  end

  # Two wordings of one fact share a signature whatever their case, punctuation, filler words or word order.
  def self.signature(text) = stems(text, skip: FILLER).uniq.sort.join(" ")

  # How well a text answers a query. One point for each asked word it holds, more for a rare word, and a boost when it
  # holds the whole phrase. rarity says how many of the texts searched hold each stem.
  def self.score(text, query_stems, phrase, rarity:, total:)
    held = stems(text).to_set
    found = query_stems.uniq.select { |word| held.include?(word) }
    return 0.0 if found.empty?

    weight = found.sum { |word| 1 + Math.log((total + 1).to_f / (rarity.fetch(word, 0) + 1)) }
    weight += PHRASE_WEIGHT if phrase.present? && squished(text).include?(phrase)
    weight
  end

  def self.squished(text) = text.to_s.downcase.scan(TOKEN).join(" ")

  # A light suffix stripper, enough for English plurals and verb forms. A word with a digit is a name and kept whole.
  def self.stem(word)
    return word if word.length <= 3 || word.match?(/\d|[-_.]/)

    stemmed = case word
    when /ies\z/ then "#{word.delete_suffix('ies')}y"
    when /sses\z/ then word.delete_suffix("es")
    when /(ss|us|is)\z/ then word
    when /s\z/ then word.delete_suffix("s")
    when /ing\z/ then undoubled(word.delete_suffix("ing"))
    when /ed\z/ then undoubled(word.delete_suffix("ed"))
    when /ly\z/ then word.delete_suffix("ly")
    else word
    end
    stemmed = stemmed.delete_suffix("e") if stemmed.length > 4
    stemmed.length >= 3 ? stemmed : word
  end

  def self.undoubled(stem) = stem.match?(/([b-df-hj-np-tv-z])\1\z/) && !stem.end_with?("ll", "ss") ? stem.chop : stem
  private_class_method :undoubled
end

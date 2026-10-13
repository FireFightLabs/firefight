# Puts values in place of the {{...}} references in a value, through strings, hashes and arrays. A string that is only
# one reference keeps the referenced value's own type, so a number stays a number and a list a list. Runbook inputs and
# workflow step data both fill this way.
module Placeholders
  module_function

  # The block is given each reference and answers its value, or MISSING to leave the reference as it was written.
  MISSING = Object.new.freeze

  def fill(value, pattern, &lookup)
    case value
    when String
      whole = value.match(/\A#{pattern}\z/)
      return found_or(lookup.call(whole[1]), value) if whole

      value.gsub(pattern) { found_or(lookup.call(Regexp.last_match(1)), Regexp.last_match(0)).to_s }
    when Hash then value.transform_values { |inner| fill(inner, pattern, &lookup) }
    when Array then value.map { |inner| fill(inner, pattern, &lookup) }
    else value
    end
  end

  # Every reference a value makes, in the order they first appear.
  def references_in(value, pattern)
    case value
    when String then value.scan(pattern).flatten
    when Hash then value.values.flat_map { |inner| references_in(inner, pattern) }
    when Array then value.flat_map { |inner| references_in(inner, pattern) }
    else []
    end.uniq
  end

  def found_or(found, written) = found.equal?(MISSING) ? written : found
end

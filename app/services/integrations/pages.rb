module Integrations
  # Reads a paged list up to a bound, and says whether it read all of it. A list cut short at the bound is never taken
  # for the whole, so a map sweep marks the kind unread (Snapshot#unread_kinds) rather than taking what it did not read
  # as gone, and says so in its gaps.
  module Pages
    Read = Data.define(:items, :complete) do
      def incomplete? = !complete
    end

    # The block is given the cursor of the page to read, nil for the first, and answers that page's items and the next
    # page's cursor, nil or empty when there is none.
    def self.read(max_pages:)
      items = []
      cursor = nil
      max_pages.times do
        page, cursor = yield(cursor)
        items.concat(Array(page))
        return Read.new(items: items, complete: true) if cursor.blank?
      end
      Read.new(items: items, complete: false)
    end
  end
end

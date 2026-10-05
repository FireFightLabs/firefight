require "test_helper"

module Integrations
  class PagesTest < ActiveSupport::TestCase
    test "a list read to its end is complete, and one cut short at the bound says so" do
      pages = { nil => [ [ 1, 2 ], "b" ], "b" => [ [ 3 ], "c" ], "c" => [ [ 4 ], nil ] }

      whole = Pages.read(max_pages: 5) { |cursor| pages.fetch(cursor) }
      assert_equal [ [ 1, 2, 3, 4 ], true ], [ whole.items, whole.complete ]

      cut = Pages.read(max_pages: 2) { |cursor| pages.fetch(cursor) }
      assert_equal [ 1, 2, 3 ], cut.items
      assert cut.incomplete?
    end
  end
end

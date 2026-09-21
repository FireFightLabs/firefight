# What a claim or a settled theory points at. A step today. A file range, a pull request or an
# Issue later, with locator saying where inside the source.
class Investigation::Citation < ApplicationRecord
  belongs_to :cited_by, polymorphic: true
  belongs_to :source, polymorphic: true
end

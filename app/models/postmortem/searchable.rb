# A postmortem is the written account, so what it says is what a later search should match.
module Postmortem::Searchable
  extend ActiveSupport::Concern
  include SearchEmbedding::Writing

  def search_facts
    { id: id, incident: incident.identifier, title: title, status: status }.compact
  end

  def search_text
    [ title, ActionView::Base.full_sanitizer.sanitize(html_content) ].compact_blank.join("\n")
  end
end

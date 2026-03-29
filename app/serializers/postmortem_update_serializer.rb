class PostmortemUpdateSerializer < BaseSerializer
  object_as :update

  type :string
  def id
    update.id
  end

  attributes(
    update_type: { type: '"generated" | "edited" | "ai_edited"' }
  )

  type "string[]"
  def changed_sections
    update.changed_sections || []
  end

  type :string
  def edited_by
    update.edited_by.user.name
  end

  type :string
  def created_at
    update.created_at.utc.iso8601
  end

  type :string, optional: true
  def html_content
    update.content&.dig("html") || render_sections(update.content)
  end

  private

  def render_sections(content)
    sections = content&.dig("sections")
    return nil if sections.blank?

    sections.map do |section|
      heading = Postmortem::SECTION_HEADINGS[section["key"]] || section["key"]
      body = ::Commonmarker.to_html(section["body"] || "", options: { parse: { smart: true }, render: { unsafe: true } })
      "<h2>#{heading}</h2>\n#{body}"
    end.join("\n")
  end
end

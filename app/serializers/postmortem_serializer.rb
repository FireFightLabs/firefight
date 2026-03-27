class PostmortemSerializer < BaseSerializer
  object_as :postmortem

  type :string
  def id
    postmortem.id
  end

  attributes(
    title: { type: :string },
    status: { type: '"draft" | "in_progress" | "in_review" | "completed"' }
  )

  type :string
  def generated_by
    postmortem.generated_by.user.name
  end

  type :string
  def created_at
    postmortem.created_at.utc.iso8601
  end

  type :string
  def updated_at
    postmortem.updated_at.utc.iso8601
  end

  type :string, optional: true
  def html_content
    sections = postmortem.sections
    return nil if sections.blank?

    sections.map do |section|
      heading = Postmortem::SECTION_HEADINGS[section["key"]] || section["key"]
      body = markdown_to_html(section["body"] || "")
      "<h2>#{heading}</h2>\n#{body}"
    end.join("\n\n")
  end

  private

  def markdown_to_html(text)
    html = text.dup
    html.gsub!(/^## (.+)$/, '<h3>\1</h3>')
    html.gsub!(/^### (.+)$/, '<h4>\1</h4>')
    html.gsub!(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
    html.gsub!(/\*(.+?)\*/, '<em>\1</em>')
    html.gsub!(/`([^`]+)`/, '<code>\1</code>')
    html.gsub!(/^```(\w*)\n(.*?)^```/m) { "<pre><code>#{$2.strip}</code></pre>" }
    html.gsub!(/^- (.+)/) { "<li>#{$1}</li>" }
    html.gsub!(/^(\d+)\. (.+)/) { "<li>#{$2}</li>" }
    html.gsub!(%r{(<li>.*?</li>\n?)+}m) { "<ul>#{$&}</ul>" }
    html.gsub!(%r{(?:^|\n)([^<\n].+?)(?=\n\n|\n<|\z)}m) do |match|
      line = $1.strip
      line.empty? ? match : "<p>#{line}</p>"
    end
    html
  end
end

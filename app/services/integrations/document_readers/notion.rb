module Integrations
  module DocumentReaders
    # Reads one Notion page through the hosted server's notion-fetch, which takes a page's address or id as id and
    # answers the page in Notion's enhanced Markdown, its title and its address (the tool's own description). The page's
    # body sits inside a content tag, which is what the handbook keeps, so its properties and the wrapper never reach a
    # page. An answer whose shape this does not read is kept whole rather than lost.
    class Notion < RemoteReader
      FETCH = "notion_fetch".freeze
      CONTENT = %r{<content>\s*(.*?)\s*</content>}m
      TITLE = /\A#\s+(.+)$/

      def page(reference)
        result = call(FETCH, { "id" => reference.to_s }, "the page #{reference}")
        raise Integrations::Error, "notion-fetch is switched off on #{settings&.name || 'this connection'}, so the page cannot be read." if result.nil?

        refused!(FETCH, result)
        answer = Capabilities::Answers.data(result)
        answer = { "text" => Capabilities::Answers.text(result) } unless answer.is_a?(Hash) && answer["text"].is_a?(String)
        body = answer["text"][CONTENT, 1] || answer["text"]
        title = answer["title"].presence || body[TITLE, 1]
        Documents::Page.new(title: title.to_s.strip.presence || "Notion page", text: body.strip, url: answer["url"].presence || reference.to_s)
      end
    end
  end
end

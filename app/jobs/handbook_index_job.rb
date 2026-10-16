# Splits a handbook page into sections for search and embeds them (HandbookService#index!). Without a model the page is
# still searched by its words.
class HandbookIndexJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(page_id)
    page = Chat::HandbookPage.find(page_id)
    HandbookService.new(page.workspace).index!(page)
  rescue FirefightAi::Error => error
    Rails.logger.info({ event: "handbook.index_unembedded", page_id: page_id, error: error.class.name }.to_json)
  end
end

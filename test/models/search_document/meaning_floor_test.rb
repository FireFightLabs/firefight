require "test_helper"

# Checks SearchDocument::Search::MEANING_FLOOR against the configured embedding model with real vectors. It calls the
# model, so it runs only when asked for (LIVE_EMBEDDINGS=1) and a key is configured, never in CI on its own.
class SearchDocument::MeaningFloorTest < ActiveSupport::TestCase
  # A question someone would type, and catalog descriptions that answer it or do not.
  SERVICES = {
    checkout: "Checkout (Service)\nHandles login, sessions and password resets for customers.",
    billing: "Billing (Service)\nCharges cards through the payment provider and records invoices.",
    notifier: "Notifier (Service)\nSends receipts and password reset emails to customers.",
    indexer: "Indexer (Service)\nKeeps the product search index in step with the catalog database.",
    reports: "Reports (Service)\nBuilds the monthly finance spreadsheets for the accounting team.",
    uploads: "Media (Service)\nStores images customers upload and serves resized copies.",
    gateway: "Edge (Service)\nRoutes public traffic to the right service and terminates TLS.",
    scheduler: "Scheduler (Service)\nRuns the nightly jobs that expire carts and retry failed orders."
  }.freeze
  # A question someone would type, the service that answers it, and services that do not.
  QUESTIONS = {
    "people cannot sign in" => [ :checkout, %i[indexer reports scheduler] ],
    "card payments failing" => [ :billing, %i[uploads gateway indexer] ],
    "emails not arriving" => [ :notifier, %i[reports gateway uploads] ],
    "search results are stale" => [ :indexer, %i[billing checkout uploads] ],
    "profile pictures are broken" => [ :uploads, %i[billing reports scheduler] ],
    "the site returns 502 for everyone" => [ :gateway, %i[reports notifier indexer] ],
    "abandoned carts are not cleared overnight" => [ :scheduler, %i[uploads gateway notifier] ],
    "finance numbers for last month are missing" => [ :reports, %i[uploads checkout gateway] ]
  }.freeze

  setup do
    skip "Set LIVE_EMBEDDINGS=1 with a model key to check the floor against real vectors" unless ENV["LIVE_EMBEDDINGS"] == "1" && RubyLLM.config.openai_api_key.present?
    @workspace = workspaces(:slack_workspace_one)
  end

  test "a description that answers the question clears the floor and one that does not stays under it" do
    related = QUESTIONS.map { |query, (answer, _)| similarity(query, SERVICES.fetch(answer)) }
    unrelated = QUESTIONS.flat_map { |query, (_, others)| others.map { |other| similarity(query, SERVICES.fetch(other)) } }
    puts "\n#{FirefightAi.embedding_model} related #{related.map { |value| value.round(3) }} unrelated #{unrelated.map { |value| value.round(3) }}"

    related.each { |value| assert_operator value, :>=, SearchDocument::Search::MEANING_FLOOR }
    unrelated.each { |value| assert_operator value, :<, SearchDocument::Search::MEANING_FLOOR }
  end

  private

  def similarity(query, text)
    first, second = [ query, text ].map { |each| (@vectors ||= {})[each] ||= FirefightAi.embed(each, workspace: @workspace).vectors }
    dot = first.zip(second).sum { |left, right| left * right }
    dot / (Math.sqrt(first.sum { |value| value**2 }) * Math.sqrt(second.sum { |value| value**2 }))
  end
end

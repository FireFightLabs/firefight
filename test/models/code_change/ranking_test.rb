require "test_helper"

class CodeChange::RankingTest < ActiveSupport::TestCase
  STARTED = Time.utc(2026, 9, 24, 14, 5)

  test "touching the failing code outranks being closer in time" do
    close = change(repository: "acme/billing", at: STARTED - 5.minutes, files: [ "lib/tax.rb" ])
    touching = change(repository: "acme/checkout", at: STARTED - 5.hours, files: [ "app/models/pool.rb" ])

    ranked = ranking(paths: [ "app/app/models/pool.rb" ]).rank([ close, touching ])

    assert_equal [ touching, close ], ranked.map(&:change)
    assert_includes ranked.first.reasons, "changes app/models/pool.rb, which the stack trace runs through"
  end

  test "a deploy outranks the same kind of merge, and a merge says it is not proof of a deploy" do
    deploy = change(kind: CodeChange::Ranking::KIND_DEPLOY, at: STARTED - 1.hour, environment: "production")
    merge = change(kind: CodeChange::Ranking::KIND_MERGE, at: STARTED - 1.hour)

    ranked = ranking.rank([ merge, deploy ])

    assert_equal deploy, ranked.first.change
    assert_includes ranked.last.reasons, "was merged, which is not proof it was deployed"
  end

  test "config and migrations count against a change, and a place the clues name counts too" do
    risky = change(repository: "acme/checkout", files: [ "db/migrate/20260924_add_index.rb" ])

    reasons = ranking(places: [ "checkout" ]).rank([ risky ]).first.reasons

    assert_includes reasons, "is in acme/checkout, which the clues name"
    assert_includes reasons, "changes database migrations"
  end

  test "a change after the start is left out, since it cannot have caused it" do
    assert_empty ranking.rank([ change(at: STARTED + 1.minute) ])
  end

  private

  def ranking(paths: [], places: [])
    CodeChange::Ranking.new(started: STARTED, window: 6.hours, paths: paths, places: places)
  end

  def change(repository: "acme/checkout", kind: CodeChange::Ranking::KIND_DEPLOY, at: STARTED - 1.hour, files: [ "app/models/order.rb" ], environment: "production")
    CodeChange::Ranking::Change.new(
      repository: repository, kind: kind, sha: SecureRandom.hex(20), at: at, title: "A change", author: "grace",
      url: "https://github.com/#{repository}", pull_number: nil, files: files, environment: environment, rollback: false
    )
  end
end

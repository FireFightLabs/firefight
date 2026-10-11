# A step waiting for a deploy to go live keeps the deploy live when the watch began and counts only a newer one, or the
# commit, tag or branch named. A status reading only says what is true now, so the previous release's finished rollout
# once read as the new one done. It is all kept on the step, so a restart or a repair keeps the same baseline.
module Chat::Watch::Step::NewDeploy
  extend ActiveSupport::Concern

  Deploys = Integrations::Capabilities::Deploys
  History = Integrations::Capabilities::History

  RESOURCE = "resource".freeze
  CONNECTION = "connection".freeze
  COMMIT = "commit".freeze
  TAG = "tag".freeze
  BRANCH = "branch".freeze
  REPOSITORY = "repository".freeze
  GIVEN = [ RESOURCE, CONNECTION, COMMIT, TAG, BRANCH, REPOSITORY ].freeze
  TAG_COMMIT = "tag_commit".freeze
  TAG_UNREAD = "tag_unread".freeze
  SINCE = "since".freeze
  BASELINE = "baseline".freeze
  # Whether the provider tells one deploy from another. Without it a deploy that finished after the watch began counts.
  IDENTITY = "identity".freeze
  PROVIDER = "provider".freeze
  # Without deploys as data, the reading when the watch began, which a done can never be.
  BASELINE_DIGEST = "baseline_digest".freeze
  # The new deploy first seen live, so it is judged once at once.
  LIVE_SEEN = "live_seen".freeze

  WAITING = "waiting".freeze
  ROLLING_OUT = "rolling_out".freeze
  LIVE = "live".freeze
  FAILED = "failed".freeze
  Gate = Data.define(:state, :deploy, :words) do
    def open? = state == LIVE
  end

  # A goal, a done_when or a label of a status read that speaks of a deploy. A release alone is often a run, such as a
  # release workflow, which is followed as a run.
  DEPLOY_WORDS = /\b(roll(ed|ing|s)?[ -]?outs?|deploy(s|ed|ing|ments?)?|new (version|image|commit|build|revision|release))\b/i
  # A tool's question that speaks of a new version going live. A tool also reads runs named deploy, so the word alone is
  # not enough there.
  NEW_VERSION_WORDS = /\b(roll(ed|ing|s)?[ -]?outs?|(new|latest) (version|deploy(ment)?|rollout|release|commit|image|build|revision))\b/i

  class_methods do
    # A run in a resource's history already follows a run that started around the watch, so it never waits here.
    def waits_for_deploy?(step, key)
      return false if key == Integrations::Capabilities::HISTORY
      return true if step["new_deploy"].is_a?(Hash)
      return true if key == Integrations::Capabilities::DEPLOYS

      case key
      when Integrations::Capabilities::STATUS then step.values_at("goal", "done_when", "label").any? { |words| words.to_s.match?(DEPLOY_WORDS) }
      when Chat::Watch::Step::READ_TOOL then step.values_at("goal", "done_when").any? { |words| words.to_s.match?(NEW_VERSION_WORDS) }
      else false
      end
    end

    # The resource deployed and the commit, tag or branch named, from a step given to start_watch.
    def deploy_target(step, arguments)
      given = step["new_deploy"].is_a?(Hash) ? step["new_deploy"].transform_keys(&:to_s).slice(*GIVEN).transform_values { |value| value.to_s.strip }.compact_blank : {}
      named = arguments.to_h.slice(RESOURCE, CONNECTION).compact_blank
      named.merge(given) { |_key, from_read, from_given| from_given.presence || from_read }
    end

    # Deploys that never say how they stand, such as an observer's markers, cannot tell the new one apart either.
    def new_deploy_for(target, since:, deploys:, provider: nil)
      kept = target.merge(SINCE => since.utc.iso8601, PROVIDER => provider).compact
      identified = !deploys.nil? && (deploys.empty? || deploys.any? { |deploy| deploy.identified? && deploy.status.present? })
      kept.merge(IDENTITY => identified, BASELINE => (Deploys.live(deploys)&.to_h if identified))
    end
  end

  def waits_for_deploy? = new_deploy.present?

  def deploy_identity? = waits_for_deploy? && new_deploy[IDENTITY] == true

  def deploy_resource = new_deploy.to_h[RESOURCE]

  def deploy_since = Time.zone.parse(new_deploy.to_h[SINCE].to_s) || begun_at

  def deploy_baseline
    kept = new_deploy.to_h[BASELINE]
    kept.is_a?(Hash) ? Deploys::Deploy.from_h(kept) : nil
  end

  def unresolved_tag
    new_deploy[TAG] if waits_for_deploy? && new_deploy[TAG].present? && new_deploy[TAG_COMMIT].blank? && new_deploy[TAG_UNREAD].blank?
  end

  # No code host can read the tag, so it is matched by the deploys' own tag or version and not asked again.
  def tag_unresolvable!(why) = update_columns(new_deploy: new_deploy.merge(TAG_UNREAD => why.to_s.truncate(300)), updated_at: Time.current)

  def tag_resolved!(commit)
    return if commit.blank?

    update_columns(new_deploy: new_deploy.merge(TAG_COMMIT => commit.to_s.downcase), updated_at: Time.current)
  end

  # The new deploy was first seen live. True once, so its reading is judged at once rather than when it next changes.
  def deploy_live_seen!(deploy)
    key = deploy.id || deploy.short
    return false if new_deploy[LIVE_SEEN] == key

    update_columns(new_deploy: new_deploy.merge(LIVE_SEEN => key), updated_at: Time.current)
    true
  end

  def deploy_start_words = deploy_identity? ? waiting_words : no_identity_words

  # A reading that has not changed since the watch began cannot show a deploy that finished after it.
  def unchanged_since_baseline?(digest) = waits_for_deploy? && !deploy_identity? && new_deploy[BASELINE_DIGEST] == digest

  def deploy_gate(deploys)
    target_live = live_target(deploys)
    return gate(LIVE, target_live) if target_live

    candidates = deploys.select { |deploy| newer?(deploy, deploys) && wanted?(deploy) }
    live = Deploys.live(deploys)
    serving = candidates.find { |deploy| deploy.serving? && (live.nil? || live.same?(deploy)) }
    return gate(LIVE, serving) if serving

    newest = candidates.first
    return gate(WAITING, nil) unless newest
    return gate(FAILED, newest) if newest.failed?

    gate(ROLLING_OUT, newest)
  end

  def deploy_question
    return unless waits_for_deploy? && !deploy_identity?

    "Only a deploy of #{target_resource_words} that finished rolling out after #{clock(deploy_since)} counts as done. The first reading " \
      "shows what was already live when the watch began, so it is not the new one.#{" It must be #{target_words}." if named_target?}"
  end

  def no_identity_words
    who = new_deploy[PROVIDER].presence || "The provider"
    "Waiting for a new deploy of #{target_resource_words}. #{who} does not say which deploy is live, so one that finishes after " \
      "#{clock(deploy_since)} counts."
  end

  private

  # The commit or tag named, already the one serving, as when the watch began after it went out.
  def live_target(deploys)
    return unless pinned?

    live = Deploys.live(deploys)
    live if live&.serving? && wanted?(live)
  end

  # A commit or a tag names one exact version, wherever it sits among the deploys. A branch or nothing names a newer one.
  def pinned? = new_deploy[COMMIT].present? || new_deploy[TAG].present?

  def named_target? = pinned? || new_deploy[BRANCH].present?

  def wanted?(deploy)
    if new_deploy[COMMIT].present?
      deploy.commit?(new_deploy[COMMIT])
    elsif new_deploy[TAG].present?
      tag = new_deploy[TAG]
      deploy.tag == tag || deploy.version == tag || (new_deploy[TAG_COMMIT].present? && deploy.commit?(new_deploy[TAG_COMMIT]))
    elsif new_deploy[BRANCH].present?
      deploy.branch.nil? || deploy.branch == new_deploy[BRANCH]
    else
      true
    end
  end

  # Without a baseline, or without times, a deploy that started around the watch or sits above the baseline counts.
  def newer?(deploy, deploys)
    baseline = deploy_baseline
    return started_since_watch?(deploy) if baseline.nil?
    return false if deploy.same?(baseline)
    return deploy.started_at > baseline.started_at if deploy.started_at && baseline.started_at

    at = deploys.index { |each| each.same?(baseline) }
    at.nil? || deploys.index(deploy) < at
  end

  def started_since_watch?(deploy)
    since = deploy_since
    return true if deploy.started_at.nil? && deploy.finished_at.nil?

    (deploy.started_at && deploy.started_at >= since - Chat::Watch::Step::STARTED_BEFORE_WATCH) || (deploy.finished_at && deploy.finished_at > since)
  end

  def gate(state, deploy) = Gate.new(state: state, deploy: deploy, words: gate_words(state, deploy))

  def gate_words(state, deploy)
    case state
    when LIVE
      return "#{deploy_name(deploy)} was already live on #{target_resource_words} when the watch began." if deploy_baseline&.same?(deploy)

      "The new deploy of #{target_resource_words} is live (#{[ deploy.short, (" finished #{clock(deploy.finished_at)}" if deploy.finished_at) ].compact.join(',')})."
    when ROLLING_OUT
      "A new deploy of #{target_resource_words} is rolling out (#{[ deploy.short, (" started #{clock(deploy.started_at)}" if deploy.started_at) ].compact.join(',')})."
    when FAILED then "The new deploy of #{target_resource_words} failed (#{deploy.short})."
    else waiting_words
    end
  end

  def waiting_words
    baseline = deploy_baseline
    now = baseline ? " (live now: #{[ baseline.short, (" since #{clock(baseline.finished_at || baseline.started_at)}" if baseline.finished_at || baseline.started_at) ].compact.join})" : ""
    return "Waiting for #{target_words} to deploy to #{target_resource_words}#{now}." if pinned?
    return "Waiting for a new deploy of #{target_resource_words} from #{new_deploy[BRANCH]} to start#{now}." if new_deploy[BRANCH].present?

    "Waiting for a new deploy of #{target_resource_words} to start#{now}."
  end

  def target_words
    return new_deploy[COMMIT].first(Deploys::SHORT_COMMIT) if new_deploy[COMMIT].present?
    return new_deploy[TAG] if new_deploy[TAG].present?

    "a deploy from #{new_deploy[BRANCH]}"
  end

  def deploy_name(deploy) = pinned? ? target_words : deploy.short

  def target_resource_words = deploy_resource.presence || label

  def clock(time) = time.utc.strftime("%H:%M UTC")
end

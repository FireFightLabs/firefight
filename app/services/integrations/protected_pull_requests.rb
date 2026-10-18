module Integrations
  # An outside coding agent opens its pull request itself, so Firefight cannot refuse what it pushes. Once it opens, what
  # it changed is read through the code host that holds it and checked against the paths the workspace keeps out of code
  # changes. One that touches any is flagged for a person, with a comment on the pull request, and never closed. One whose
  # files cannot be read is flagged too, since a change nobody checked is not a clean one. An agent's answer can name any
  # address, so only a pull request in the repository the change was asked for, on a connection holding it, is read or
  # commented on, and any other is flagged unchecked with nothing written.
  module ProtectedPullRequests
    # One pull request a person must review, and why, in the words the answer, the step and the thread show.
    Flag = Data.define(:url, :sentence)

    NO_HOST = "no connected code host can read it".freeze
    NOT_ASKED = "it is not in %<repository>s, the repository the change was asked for".freeze
    BROKE = "the check failed on Firefight's side".freeze

    module_function

    # The pull requests among urls that need a person. repository is the one the change was asked for, as given. asked_by
    # is whoever asked for the change, named in the activity log beside the comment, and via the coding agent's tool the
    # change came through, whose call the comment belongs to.
    def check(workspace, urls, repository:, asked_by:, via:)
      asked = named(repository)
      asked_host = host_of(repository)
      urls.filter_map do |url|
        next unchecked(url, format(NOT_ASKED, repository: repository.to_s.strip)) unless same_host?(url, asked_host)

        flag_for(workspace, url, asked, asked_by, via)
      rescue StandardError => error
        Rails.logger.warn({ event: "protected_pull_requests.check_failed", url: url, error: error.class.name }.to_json)
        unchecked(url, BROKE)
      end
    end

    # owner/name, or a longer path on a host with groups, from a name or an address.
    def named(repository) = repository.to_s.strip.sub(%r{\A(?:https?://|git@)[^/:]+[/:]}, "").delete_suffix(".git").delete_suffix("/")

    # The host an address names, nil for a bare name. A mirror on another host is another repository.
    def host_of(repository) = repository.to_s.strip[%r{\A(?:https?://|git@)([^/:]+)}, 1]&.downcase

    def same_host?(url, asked_host) = asked_host.nil? || host_of(url) == asked_host

    def unkept?(workspace, asked) = Integration.protected_paths_for(workspace, asked).empty?

    # A pull request outside the asked repository is flagged whether or not that repository keeps any paths, since the
    # agent was not asked to open it.
    def flag_for(workspace, url, asked, asked_by, via)
      owned = PullRequests.addressed(workspace, url)
      return unchecked(url, format(NOT_ASKED, repository: asked)) if owned.any? && owned.none? { |address| address.repository.casecmp?(asked) }
      return if unkept?(workspace, asked)
      return unchecked(url, NO_HOST) if owned.empty?

      addresses = owned.select { |address| address.repository.casecmp?(asked) }

      repository = addresses.first.repository

      address, paths, failure = read_paths(addresses)
      # A host that cannot list the files may still take a comment, so the pull request itself says it went unchecked.
      unless address
        said = comment(workspace, addresses.first, url, [], CodeChange::PROTECTED_UNCHECKED_COMMENT, asked_by, via)
        return Flag.new(url: url, sentence: [ unchecked(url, failure).sentence, said ].compact.join(" "))
      end

      touched = Integration.protected_among_for(workspace, repository, paths).sort
      return if touched.empty?

      named = touched.to_sentence
      said = comment(workspace, address, url, touched, format(CodeChange::PROTECTED_COMMENT, paths: named), asked_by, via)
      Flag.new(url: url, sentence: [ format(CodeChange::PROTECTED_TOUCHED, pull_request: url, paths: named), said ].compact.join(" "))
    end

    # The first connection that can read what changed, in the order addressed gives them.
    def read_paths(addresses)
      failure = nil
      addresses.each do |address|
        return [ address, PullRequests.paths(address), nil ]
      rescue Integrations::Error => error
        failure = Sentence.clean(error)
      end
      [ nil, nil, failure ]
    end

    def unchecked(url, reason) = Flag.new(url: url, sentence: format(CodeChange::PROTECTED_UNCHECKED, pull_request: url, reason: reason))

    # Written as the code host connection and recorded as Halon's, since it is Firefight's own rule speaking
    # (Integration.record_pull_request_flag!). Answers why it could not be posted, or nil once it was.
    def comment(workspace, address, url, touched, body, asked_by, via)
      Integration.record_pull_request_flag!(workspace, via: via, url: url, paths: touched, asked_by: asked_by) do
        PullRequests.flag!(address, body)
      end
      nil
    rescue Integrations::Error => error
      format(CodeChange::PROTECTED_COMMENT_FAILED, reason: Sentence.clean(error))
    end
  end
end

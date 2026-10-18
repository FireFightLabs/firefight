module Integrations
  # An outside coding agent opens its pull request itself, so Firefight cannot refuse what it pushes. Once it opens, what
  # it changed is read through the code host that holds it and checked against the paths the workspace keeps out of code
  # changes. One that touches any is flagged for a person, with a comment on the pull request, and never closed. One whose
  # files cannot be read is flagged too, since a change nobody checked is not a clean one.
  module ProtectedPullRequests
    # One pull request a person must review, and why, in the words the answer, the step and the thread show.
    Flag = Data.define(:url, :sentence)

    NO_HOST = "no connected code host can read it".freeze

    module_function

    # The pull requests among urls that need a person. asked_by is whoever asked for the change, named in the activity log
    # beside the comment, and via the coding agent's tool the change came through, whose call the comment belongs to.
    def check(workspace, urls, asked_by:, via:)
      urls.filter_map { |url| flag_for(workspace, url, asked_by, via) }
    end

    def flag_for(workspace, url, asked_by, via)
      addresses = PullRequests.addressed(workspace, url)
      repository = addresses.first&.repository || CodeChange.repository_name(url) || url
      return if Integration.protected_paths_for(workspace, repository).empty?
      return unchecked(url, NO_HOST) if addresses.empty?

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

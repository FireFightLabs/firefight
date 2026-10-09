# How each repository a code host connection holds is set up before its tests (RepositorySetup), and what an admin may
# add under the connection's Code changes.
module Integration::RepositorySetups
  extend ActiveSupport::Concern

  # owner/name, or a path with groups such as acme/platform/api.
  REPOSITORY_NAME = %r{\A[\w.\-]+(/[\w.\-]+)+\z}

  # Why a setup cannot be added for repository, or nil when it can.
  def repository_setup_blocked_reason(repository)
    return "#{display_name} holds no code, so it has no repositories to set up." unless holds_code?

    name = repository.to_s.strip
    return "Name the repository, such as acme/api." if name.empty?
    return "#{name} is not a repository name. Write it as owner/name, such as acme/api." unless name.match?(REPOSITORY_NAME) && !name.include?("..")
    return "#{name} already has a setup here. Edit it, or read it from CI again." if repository_setups.exists?(repository: name)

    nil
  end

  # Why the connection's CI cannot be read now, or nil when it can.
  def ci_read_blocked_reason
    return "#{display_name} holds no code, so it has no CI to read." unless holds_code?
    return "#{display_name} has no environment switched on, so its CI cannot be read." unless resolve_environment(nil)

    nil
  end

  # What the toast says once a setup was read from CI.
  def repository_setup_read_words(setup)
    said = "Read #{setup.repository}'s setup from #{setup.derived_from}."
    left_out = setup.unstartable_services(images: SandboxProviders.runs_images?(workspace))
    return said if left_out.empty?

    "#{said} The sandbox cannot start #{left_out.to_sentence}, so Halon prepares #{setup.repository} without #{left_out.one? ? 'it' : 'them'}."
  end
end

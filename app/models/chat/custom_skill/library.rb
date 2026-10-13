# A workspace's copy of one of Firefight's skills. It keeps the library skill's name, so Halon uses it in that skill's
# place, and remembers the library version it came from with what that version said (library_base). When Firefight
# ships a newer version the copy is told, with what changed, and is never changed under the workspace. A person takes the
# new version or keeps their own (library_dismissed_version), and is told again only of a version newer than that.
module Chat::CustomSkill::Library
  extend ActiveSupport::Concern

  class_methods do
    # Why the workspace cannot copy one of Firefight's skills, or nil. It has one copy of each, under its own skills.
    def copy_blocked_reason(library_skill, workspace: nil, copied: nil)
      copied ||= live.where(workspace: workspace).pluck(:library_name)
      "You already have a copy of #{library_skill.name}, under Your skills." if copied.include?(library_skill.name)
    end

    def copy!(library_skill, workspace:, by:)
      create_with!(
        workspace: workspace, name: library_skill.name, content: library_skill.content, by: by,
        author_kind: Chat::CustomSkill::Version::AUTHOR_FIREFIGHT, reason: "Copied from Firefight's library, version #{library_skill.version}.",
        source: library_skill.source, domain: library_skill.domain, library_name: library_skill.name,
        library_version: library_skill.version, library_base: library_skill.content
      )
    end
  end

  def copy? = library_name.present?

  def library_skill = (Chat::Skill.find(library_name) if copy?)

  # The library's newer version this copy has not been told about yet, or nil.
  def library_update
    skill = library_skill
    return unless skill
    return unless skill.version > library_version.to_i && skill.version > library_dismissed_version.to_i

    skill
  end

  # Replaces the copy's words with the library's newer version, as a version the person who chose it wrote.
  def take_library!(by:)
    skill = library_update
    raise Chat::CustomSkill::Writing::Refused, "There is no newer version of #{library_name} to take." unless skill

    write!(skill.content, by: by, reason: "Took Firefight's version #{skill.version}.",
                          library_version: skill.version, library_base: skill.content, library_dismissed_version: nil)
  end

  # Keeps the workspace's own words, so the copy is told again only of a version newer than this one.
  def keep_own!
    skill = library_update
    raise Chat::CustomSkill::Writing::Refused, "There is no newer version of #{library_name} to keep yours over." unless skill

    update!(library_dismissed_version: skill.version)
  end
end

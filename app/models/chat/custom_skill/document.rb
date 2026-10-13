# A skill as a SKILL.md file: front matter naming it, when it is used and the tools it needs, then its steps. It is the
# format of Firefight's own skills in config/skills, with description beside when so other agents that read SKILL.md
# files find what they expect. Reading takes either, and takes allowed-tools when tools is missing.
module Chat::CustomSkill::Document
  FILE_NAME = "SKILL.md".freeze
  SIZE_LIMIT = 64.kilobytes

  # A file that is not a skill, with the sentence that says why.
  class Unreadable < StandardError; end

  Parsed = Data.define(:name, :content)

  module_function

  # The file's skill for a workspace: the next version of its skill of that name, its copy of Firefight's of that name,
  # or a new skill. Returns the skill and the version written over one that was live, nil when nothing was. A skill only
  # Halon has proposed takes the file as its first live version, and the proposal stays waiting, to edit or dismiss.
  def import!(parsed, workspace:, by:)
    name = Chat::CustomSkill.normalize_value_for(:name, parsed.name)
    reason = "Imported from a #{FILE_NAME} file."
    existing = Chat::CustomSkill.where(workspace: workspace).find_by(name: name)
    if existing && !existing.dormant?
      was_live = existing.live_version_id.present?
      written = existing.write!(parsed.content, by: by, reason: reason)
      return [ existing, (written if was_live) ]
    end

    library = Chat::Skill.library_for(workspace).find { |skill| skill.name == name }
    Chat::CustomSkill.transaction do
      next [ Chat::CustomSkill.create_with!(workspace: workspace, name: name, content: parsed.content, by: by, reason: reason), nil ] unless library

      copy = Chat::CustomSkill.copy!(library, workspace: workspace, by: by)
      copy.write!(parsed.content, by: by, reason: reason)
      [ copy, nil ]
    end
  end

  def render(definition)
    meta = { "name" => definition.name, "description" => definition.used_when, "when" => definition.used_when, "tools" => definition.tools }
    meta["references"] = definition.references if definition.references.any?
    meta["signals"] = definition.signals if definition.signals.any?
    "#{meta.to_yaml}---\n\n#{definition.steps}\n"
  end

  def parse(text)
    text = text.to_s.dup.force_encoding(Encoding::UTF_8)
    raise Unreadable, "The file is larger than #{SIZE_LIMIT / 1.kilobyte} KB, which no skill needs." if text.bytesize > SIZE_LIMIT
    raise Unreadable, "The file is not text." unless text.valid_encoding?

    header, steps = text.delete_prefix("﻿").gsub("\r\n", "\n").match(Chat::Skill::FRONT_MATTER)&.captures
    raise Unreadable, "The file has no front matter, the part between two --- lines that names the skill." unless header

    meta = YAML.safe_load(header)
    raise Unreadable, "The front matter is not a list of names and values." unless meta.is_a?(Hash)

    name = meta["name"].to_s.strip
    raise Unreadable, "The front matter has no name." if name.empty?

    Parsed.new(name: name, content: {
      "when" => (meta["when"].presence || meta["description"]).to_s,
      "tools" => listed(meta.key?("tools") ? meta["tools"] : meta["allowed-tools"]),
      "steps" => steps.to_s.strip,
      "references" => listed(meta["references"]),
      "signals" => listed(meta["signals"])
    })
  rescue Psych::Exception
    raise Unreadable, "The front matter is not readable YAML."
  end

  # A list in the front matter, or one line of names split by commas or spaces.
  def listed(value) = value.is_a?(Array) ? value.map(&:to_s) : value.to_s.split(/[\s,]+/).compact_blank
end

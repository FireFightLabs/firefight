# The tools a workspace's own skill can name: every tool Halon can be offered here by the name it calls it (the same
# choices a runbook step picks from), and Halon's own reads that are not tools of Firefight's MCP server. A copy of one of
# Firefight's skills may also keep the names its library skill uses, which for a provider's skill are the provider's own.
# Whoever writes a skill's words checks them here first, the Skills page and Halon's proposal alike.
module Chat::Tools::SkillTools
  GROUP_OWN = "Halon's own reads".freeze

  Choice = Data.define(:name, :group, :description)

  OWN = [
    Choice.new(name: Chat::Tools::WhatChanged::NAME, group: GROUP_OWN, description: ResourceMap::Timeline::DESCRIPTION),
    Choice.new(name: Chat::Tools::KeyQuery::NAME, group: GROUP_OWN, description: ResourceMap::KeyQueries::DESCRIPTION),
    Choice.new(name: Chat::Tools::LogPatterns::NAME, group: GROUP_OWN, description: ResourceMap::LogTemplate::DESCRIPTION),
    Choice.new(name: Chat::Tools::OutsideCheck::NAME, group: GROUP_OWN,
               description: "Checks an address from outside as a user meets it: reachability, status, certificate and DNS."),
    Choice.new(name: Chat::Tools::Browser::NAME, group: GROUP_OWN,
               description: "Opens a page in a real browser, follows a short path and reads what it shows.")
  ].freeze

  module_function

  def choices(workspace)
    picked = Chat::Tools::Choices.tools(workspace).map do |choice|
      Choice.new(name: choice.name, group: choice.group, description: choice.description)
    end
    (picked + OWN).uniq(&:name)
  end

  # The tools named that Halon does not have here, for a skill drawn from source (a provider's key, firefight or the
  # workspace's own) with the tools its library skill names when it is a copy.
  def unknown(workspace, tools, source: Chat::Skill::SOURCE_WORKSPACE, library_tools: [])
    known = choices(workspace).map(&:name) + Array(library_tools)
    known += provider_handles(workspace, source) unless source.in?([ Chat::Skill::SOURCE_WORKSPACE, Chat::Skill::SOURCE_FIREFIGHT ])
    Array(tools).map { |tool| tool.to_s.strip }.compact_blank - known
  end

  # Why the tools cannot be kept, as a sentence, or nil. A new skill is checked as the workspace's own unless it is a copy.
  def problem(workspace, tools, skill: nil, library: nil)
    source = skill&.source || library&.source || Chat::Skill::SOURCE_WORKSPACE
    library_tools = Array(skill&.library_base.to_h["tools"]) + Array(library&.tools)
    missing = unknown(workspace, tools, source: source, library_tools: library_tools)
    return if missing.empty?

    "#{missing.to_sentence} #{missing.one? ? 'is not a tool' : 'are not tools'} Halon has in this workspace."
  end

  # A provider's tools by the name the provider gives them, which its skills and their copies use.
  def provider_handles(workspace, provider)
    workspace.switched_on_tools.select { |tool| tool.integration.provider == provider }.map(&:name) + [ Chat::Tools::UseSkill::MAP ]
  end
end

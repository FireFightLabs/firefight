# A workflow as a file another workspace can import: its name, what it does, its other names, and the trigger, steps,
# edges and outputs of one version. Importing makes a new workflow whose first version is a draft holding the file, so
# nothing runs until someone publishes it. A step that needs a credential names a connection, so a file never carries one,
# and a file that looks like it does is refused.
module Workflow::Document
  FORMAT = "firefight.workflow".freeze
  FORMAT_VERSION = 1
  EXTENSION = ".workflow.json".freeze
  SIZE_LIMIT = 512.kilobytes

  # A file that is not a workflow, with the sentence that says why.
  class Unreadable < StandardError; end

  Parsed = Data.define(:name, :description, :aliases, :content)

  module_function

  def render(workflow, version = workflow.live_version || workflow.draft)
    JSON.pretty_generate({ "format" => FORMAT, "format_version" => FORMAT_VERSION, "name" => workflow.name, "description" => workflow.description,
                           "aliases" => workflow.aliases, **version.snapshot })
  end

  def file_name(workflow) = "#{workflow.slug}#{EXTENSION}"

  def parse(text)
    text = text.to_s.dup.force_encoding(Encoding::UTF_8)
    raise Unreadable, "The file is larger than #{SIZE_LIMIT / 1.kilobyte} KB, which no workflow needs." if text.bytesize > SIZE_LIMIT

    data = JSON.parse(text)
    raise Unreadable, "The file is not a Firefight workflow." unless data.is_a?(Hash) && data["format"] == FORMAT
    raise Unreadable, "The file was written by a newer Firefight than this one." if data["format_version"].to_i > FORMAT_VERSION

    content = data.slice(*Workflow::Version::CONTENT).reverse_merge("trigger" => Workflow::Trigger.default, "steps" => [], "edges" => [], "outputs" => {})
    problem = Workflow::Version.content_problem(content)
    raise Unreadable, problem if problem

    Parsed.new(name: data["name"].to_s.squish, description: data["description"].presence, aliases: Array(data["aliases"]).map(&:to_s), content: content)
  rescue JSON::ParserError
    raise Unreadable, "The file is not readable JSON."
  end

  # A new workflow holding the file as a draft, named as the file names it unless name is given.
  def import!(parsed, workspace:, by:, name: nil)
    name = name.to_s.squish.presence || parsed.name
    taken = Workflow.name_taken_reason(workspace, name)
    raise Unreadable, taken if taken

    Workflow.transaction do
      workflow = Workflow.create!(workspace: workspace, name: name, description: parsed.description, aliases: parsed.aliases, created_by: by)
      workflow.versions.create!(number: 1, status: Workflow::Version::STATUS_DRAFT, author_kind: Workflow::AUTHOR_PERSON, author: by,
                                reason: "Imported from a file.", **parsed.content.symbolize_keys)
      workflow
    end
  end
end

# How one repository in a code host connection is set up before its tests, as an admin reads and edits it.
class RepositorySetupSerializer < BaseSerializer
  object_as :setup

  type :string
  def id = setup.id

  type :string
  def repository = setup.repository

  type "{ name: string; image: string | null; port: number | null; env: Record<string, string> }[]"
  def services = setup.service_list.map { |service| { name: service.name, image: service.image, port: service.port, env: service.env } }

  type "Record<string, string>"
  def env = setup.env

  type "string[]"
  def commands = setup.commands

  # What reading it from CI left out, and why, as sentences.
  type "string[]"
  def notes = setup.notes

  # The CI file and job it was read from, nil for one set up by hand.
  type :string, optional: true
  def derived_from = setup.derived_from

  type :string, optional: true
  def derived_at = setup.derived_at&.utc&.iso8601

  type :string, optional: true
  def edited_at = setup.edited_at&.utc&.iso8601

  # The services the sandbox cannot start, which it leaves out when it prepares the repository. Where the workspace's
  # boxes run containers, a service with an image starts from it.
  type "string[]"
  def unstartable_services = setup.unstartable_services(images: SandboxProviders.runs_images?(setup.workspace))
end

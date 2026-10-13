# Where a workflow and a run are read, as a link Halon or an outside agent hands a person: on Firefight's own address
# when it is set, else the path alone.
module Workflow::Links
  module_function

  def page(workflow) = AppUrl.absolute(routes.workflow_path(workflow))

  def run(run) = AppUrl.absolute(routes.workflow_run_path(run.workflow_id, run))

  def routes = Rails.application.routes.url_helpers
end

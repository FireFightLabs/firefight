# Where a workflow and a run are read, as a link Halon or an outside agent hands a person: on Firefight's own address
# when it is set, else the path alone.
module Workflow::Links
  # The canvas draws the run its address names (WorkflowCanvasController::RUN_QUERY_PARAM).
  RUN_PARAM = "run".freeze

  module_function

  def page(workflow) = AppUrl.absolute(routes.workflow_path(workflow))

  def run(run) = AppUrl.absolute(routes.workflow_path(run.workflow_id, RUN_PARAM => run.id))

  def routes = Rails.application.routes.url_helpers
end

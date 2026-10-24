# A step's output pinned on a draft, so a test run tries the steps after it without calling it again. A pin is a test
# aid, never content. A published version runs every step, and pins ride along to the next draft opened from it. Each
# pin is written with one guarded update on the draft, so a pin never lands on a version that was published meanwhile.
module Workflow::Version::Pins
  extend ActiveSupport::Concern

  KEY_OUTPUT = "output".freeze
  KEY_ROUTE = "route".freeze
  KEY_PINNED_BY = "pinned_by_id".freeze
  KEY_PINNED_AT = "pinned_at".freeze
  KEY_FROM_RUN = "from_run_id".freeze

  def pin!(step_id:, output:, by:, route: nil, from_run: nil)
    raise Workflow::Edit::Refused, "Only a draft's steps are pinned, so open a draft first." unless draft?
    raise Workflow::Edit::Refused, "That step is no longer in the workflow." unless steps_by_id.key?(step_id)
    raise Workflow::Edit::Refused, "A pinned output is a set of named values, such as {\"count\": 3}." unless output.is_a?(Hash)

    problem = self.class.secret_problem(output)
    raise Workflow::Edit::Refused, problem if problem

    entry = { KEY_OUTPUT => output, KEY_ROUTE => route.presence, KEY_PINNED_BY => by&.id, KEY_PINNED_AT => Time.current.iso8601,
              KEY_FROM_RUN => from_run&.id }.compact
    moved = self.class.where(id: id, status: Workflow::Version::STATUS_DRAFT)
                      .update_all([ "pins = pins || ?::jsonb, updated_at = ?", { step_id => entry }.to_json, Time.current ])
    raise Workflow::Edit::Refused, "Only a draft's steps are pinned, so open a draft first." unless moved == 1

    signal_workflow_page
    reload
  end

  def unpin!(step_id)
    moved = self.class.where(id: id, status: Workflow::Version::STATUS_DRAFT).where("pins ? :step", step: step_id)
                      .update_all([ "pins = pins - ?, updated_at = ?", step_id, Time.current ])
    raise Workflow::Edit::Refused, "That step's output is not pinned." unless moved == 1

    signal_workflow_page
    reload
  end

  # The pins as stand ins a run reads, by step id, for the steps the given content still has.
  def pinned_stand_ins(content = snapshot)
    ids = Workflow::Version.all_steps(content["steps"]).map { |step| step["id"] }
    pins.to_h.slice(*ids).transform_values { |pin| pin.slice(KEY_OUTPUT, KEY_ROUTE) }
  end
end

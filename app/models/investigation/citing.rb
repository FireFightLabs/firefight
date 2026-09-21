# How a run turns the step numbers the agent cites into the steps themselves, refusing a number
# that points at nothing or at a call that failed.
module Investigation::Citing
  extend ActiveSupport::Concern

  def next_step_position = (steps.maximum(:position) || 0) + 1

  def cited_steps!(numbers, what:)
    wanted = Array(numbers).map(&:to_i).uniq
    raise Investigation::Evidence::Refused, "#{what} cites no step. Say which steps showed it." if wanted.empty?

    found = steps.where(position: wanted).index_by(&:position)
    wanted.map { |number| citable!(found[number], number, what) }
  end

  private

  def citable!(step, number, what)
    raise Investigation::Evidence::Refused, "#{what} cites step #{number}, which does not exist. #{citable_range}" unless step
    return step if step.status == Investigation::Step::STATUS_SUCCEEDED

    raise Investigation::Evidence::Refused, "#{what} cites step #{number}, which failed and so showed nothing. #{citable_range}"
  end

  def citable_range
    last = steps.maximum(:position)
    last ? "The steps in this run are 1 to #{last}." : "No tool has been called in this run yet."
  end
end

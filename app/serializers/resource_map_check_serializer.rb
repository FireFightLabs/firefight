# One of a resource's key checks on the map page: what it reads, through which connection, its normal, and whether the
# person may run it.
class ResourceMapCheckSerializer < BaseSerializer
  object_as :listed

  type :string
  def key = plan.check.key

  type :string
  def label = plan.check.label

  # Which of its metrics it reads here, in words, for a check that can read more than one, such as 5xx responses.
  type :string, optional: true
  def reads = plan.reads

  type :string, optional: true
  def connection = plan.connection

  # What normal looks like for it over the last week, such as "usually 80 ms, 95% under 133 ms".
  type :string, optional: true
  def normal = plan.baseline&.normal_text

  type :boolean
  def reads_metric = plan.check.metric?

  type :boolean
  def available = plan.available?

  # Why it cannot be run here, by anyone when it is not available, or by this person when they lack the grant.
  type :string, optional: true
  def run_blocked_reason = listed.run_blocked_reason

  private

  def plan = listed.plan
end

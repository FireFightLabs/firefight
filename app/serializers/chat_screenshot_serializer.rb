# A page Halon's browser saw, for the card under the step that took it. The image is served by whichever page decided
# the reader may see it, which names its address as `screenshot_path`.
class ChatScreenshotSerializer < BaseSerializer
  object_as :screenshot

  type :string
  def id = screenshot.id

  type :string, optional: true
  def tool_call_id = screenshot.tool_call_id

  # The run step that took it, for a check an investigation made.
  type :number, optional: true
  def step_position = screenshot.step_position

  # The fix step that took it, for a page checked at the end of a fix.
  type :string, optional: true
  def remediation_step_id = screenshot.remediation_step_id

  type :string
  def viewport_label = screenshot.viewport_label

  type :string
  def caption = screenshot.caption

  type :string, optional: true
  def page_url = screenshot.page_url.presence

  # The step a check stopped before, since it would send data. Absent when it stopped for nothing it would send.
  type :number, optional: true
  def stopped_step = screenshot.stopped_step

  type :string
  def path = options.fetch(:screenshot_path).call(screenshot)
end

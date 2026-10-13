# A moment written into what a confirmation asks, such as when a workflow would run, which each surface shows in its
# reader's own time zone: the dashboard in the browser's, with the zone named, and Slack as it formats dates.
module Chat::TimeToken
  PATTERN = /\{\{at:(\d+)\}\}/

  module_function

  def for(time) = "{{at:#{time.to_i}}}"

  # The text with each moment put in its place by the block, given the time.
  def replace(text) = text.to_s.gsub(PATTERN) { yield Time.zone.at(Regexp.last_match(1).to_i) }
end

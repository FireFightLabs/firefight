# Once a day, which provider skills name tools their provider no longer offers (Chat::SkillProblem.check!).
class SkillCheckJob < ApplicationJob
  queue_as :background

  def perform
    Chat::SkillProblem.check!
  end
end

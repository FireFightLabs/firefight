# A tool a skill can name, as the skill editor offers it: the name Halon calls it, the group a person finds it under and
# what it does.
class HalonSkillToolChoiceSerializer < BaseSerializer
  object_as :choice

  type :string
  def name = choice.name

  type :string
  def group = choice.group

  type :string
  def description = choice.description
end

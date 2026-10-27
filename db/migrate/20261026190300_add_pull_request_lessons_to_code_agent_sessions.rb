# How a person treated a pull request Halon opened, read once it merged or closed: what they changed before merging or
# why they closed it. It is kept so a cause that repeats across Halon's pull requests in a repository can become a
# lesson, and read once, so a merge heard twice never teaches twice.
class AddPullRequestLessonsToCodeAgentSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :code_agent_sessions, :pull_request_outcome, :jsonb
    add_column :code_agent_sessions, :pull_request_lesson_read_at, :datetime
  end
end

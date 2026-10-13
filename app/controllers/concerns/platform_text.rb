# What people wrote in the chat platform is kept in its own markup, and a page shows it as the platform reads it
# (PlatformAdapter#messages_as_text). Serializers read the result as their platform_texts option.
module PlatformText
  extend ActiveSupport::Concern

  private

  def platform_texts(texts) = platform_texts_in(current_workspace, texts)

  def platform_texts_in(workspace, texts)
    wanted = texts.compact.uniq
    wanted.empty? ? {} : WorkspaceAdapter.for(workspace).messages_as_text(texts: wanted)
  end

  def investigation_platform_texts(investigation) = platform_texts(investigation ? investigation.said_in_platform : [])
end

# DeepSeek retired V4 Flash. Its own API serves V4.1 Flash as deepseek-flash, and OpenRouter names it
# deepseek/deepseek-v4.1-flash. A chat, an AI account or an operator override still on the old name moves to the new one.
class MoveDeepseekV4FlashChoicesToV41Flash < ActiveRecord::Migration[8.1]
  RENAMES = {
    "deepseek" => { "deepseek-v4-flash" => "deepseek-flash" },
    "openrouter" => { "deepseek/deepseek-v4-flash" => "deepseek/deepseek-v4.1-flash" }
  }.freeze

  class Conversation < ActiveRecord::Base
    self.table_name = "conversations"
  end

  class WorkspaceAiAccount < ActiveRecord::Base
    self.table_name = "workspace_ai_accounts"
  end

  class AiModelOverride < ActiveRecord::Base
    self.table_name = "ai_model_overrides"
  end

  def up = rename(RENAMES)

  # A rollback leaves every row on V4.1 Flash, since the rows this moved cannot be told apart from those that chose it
  # themselves, and putting those back on a retired model would undo a choice nobody asked to undo.
  def down; end

  private

  def rename(renames)
    renames.each do |provider, models|
      models.each do |from, to|
        AiModelOverride.where(provider: provider, model: from).update_all(model: to)
        WorkspaceAiAccount.where(provider: provider).find_each do |account|
          next unless account.models.value?(from)

          account.update_columns(models: account.models.transform_values { |model| model == from ? to : model })
        end
      end
    end

    # A chat keeps the model it was switched to without its provider. Each old name is one only its own provider offers
    # in a chat's picker, so the name alone says which it was.
    renames.values.reduce(:merge).each { |from, to| Conversation.where(chosen_model: from).update_all(chosen_model: to) }
  end
end

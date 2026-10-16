class AddCardsToChatWatches < ActiveRecord::Migration[8.1]
  def change
    change_table :chat_watches, bulk: true do |t|
      t.string :thread_card_channel_id
      t.string :thread_card_message_id
      t.datetime :thread_card_claimed_at
      t.string :direct_card_channel_id
      t.string :direct_card_message_id
      t.datetime :direct_card_claimed_at
      t.text :end_reason
      t.index [ :direct_card_channel_id, :direct_card_message_id ], name: "index_chat_watches_on_direct_card"
    end
  end
end

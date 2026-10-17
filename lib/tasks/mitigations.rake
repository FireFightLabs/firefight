namespace :mitigations do
  # A process still running the last release can write a change in a state from before while the deploy rolls out, after
  # the migrations moved every such row. Run this once the deploy is done to move those too. It repeats the migrations'
  # moves, so it is safe to run again. Remove it with Chat::Mitigation::OLD_UNDO_STATES in the release after.
  desc "Move temporary changes left in an undo state from before to the chat, once the deploy is done"
  task move_old_undo_states: :environment do
    %w[20261017100500_move_unwritten_undos_to_the_chat 20261017120100_say_a_change_put_back_in_the_chat_is_marked_back
       20261017120200_move_undos_by_hand_to_the_chat].each { |file| require Rails.root.join("db/migrate/#{file}") }

    ActiveRecord::Migration.suppress_messages do
      [ MoveUnwrittenUndosToTheChat, SayAChangePutBackInTheChatIsMarkedBack, MoveUndosByHandToTheChat ].each { |migration| migration.new.up }
    end
  end
end

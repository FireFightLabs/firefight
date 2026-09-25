namespace :operator do
  # For an operator who lost both their phone and their recovery codes. Their next visit starts setup again.
  desc "Remove an operator's authenticator: bin/rails 'operator:reset_authenticator[USER_ID]'"
  task :reset_authenticator, [ :user_id ] => :environment do |_task, args|
    user = User.find(args.fetch(:user_id))
    removed = Operator::Credential.where(user: user).delete_all
    puts removed.positive? ? "Removed the authenticator for #{user.email}. They set up a new one on their next visit." : "#{user.email} had no authenticator."
  end
end

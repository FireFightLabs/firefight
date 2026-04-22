namespace :invite_codes do
  desc "Create an invite code: rake 'invite_codes:create[CODE,EXPIRES_IN_DAYS]'"
  task :create, [ :code, :expires_in_days ] => :environment do |_, args|
    raw_code = args[:code].presence || SecureRandom.alphanumeric(12).upcase
    expires_at = args[:expires_in_days].present? ? args[:expires_in_days].to_i.days.from_now : nil

    invite_code = InviteCode.create!(
      code_digest: InviteCode.digest_code(raw_code),
      expires_at: expires_at
    )

    puts "Invite code created. Save this now; it will not be shown again."
    puts "Code: #{raw_code}"
    puts "ID: #{invite_code.id}"
    puts "Expires at: #{invite_code.expires_at || 'never'}"
  rescue ActiveRecord::RecordNotUnique
    abort "A code with this digest already exists. Pick a different code."
  end
end

require "rotp"

module Operator
  # An operator's authenticator, a TOTP secret plus single use recovery codes. Who counts as an operator is set by
  # OPERATOR_USER_IDS, read on every request, so only a deploy can change it.
  class Credential < ApplicationRecord
    self.table_name = "operator_credentials"

    OPERATOR_IDS_ENV = "OPERATOR_USER_IDS".freeze
    ISSUER = "Firefight Operator".freeze
    RECOVERY_CODE_COUNT = 10
    MAX_FAILED_ATTEMPTS = 5
    LOCKOUT = 15.minutes
    # How long a correct code keeps the console unlocked in one session.
    VERIFIED_FOR = 12.hours
    # Also accepts the code from the previous 30 second step, to allow for clock drift.
    DRIFT_SECONDS = 30

    LOCKED_MESSAGE = "Too many wrong codes. Try again in 15 minutes.".freeze
    WRONG_MESSAGE = "That code is not right. Check your authenticator app and try again.".freeze

    belongs_to :user

    encrypts :totp_secret

    scope :confirmed, -> { where.not(confirmed_at: nil) }

    def self.for(user) = user && find_by(user: user)

    def self.operator?(user)
      user.present? && ENV.fetch(OPERATOR_IDS_ENV, "").split(",").map(&:strip).include?(user.id)
    end

    # Reuses the unconfirmed secret, so a mistyped first code does not mean scanning the QR code again.
    def self.start_for!(user)
      find_by(user: user) || create!(user: user, totp_secret: ROTP::Base32.random)
    rescue ActiveRecord::RecordNotUnique
      find_by!(user: user)
    end

    # The secret in groups of four, for typing it into an app by hand.
    def display_secret = totp_secret.scan(/.{1,4}/).join(" ")

    # The QR code as a grid of dark and light modules. The page draws them, so no HTML is sent to the browser.
    def qr_modules = RQRCode::QRCode.new(provisioning_uri, level: :m).modules

    def confirmed? = confirmed_at.present?

    def locked? = locked_until.present? && locked_until.future?

    def provisioning_uri
      ROTP::TOTP.new(totp_secret, issuer: ISSUER).provisioning_uri(user.email.presence || user.id)
    end

    # Confirms setup with the first code and returns the recovery codes once. Only their digests are stored.
    def confirm!(code)
      return nil unless attempt { verify_code(code) }

      codes = Array.new(RECOVERY_CODE_COUNT) { SecureRandom.alphanumeric(10).downcase.scan(/.{5}/).join("-") }
      update!(confirmed_at: Time.current, recovery_code_digests: codes.map { |recovery| digest(recovery) })
      codes
    end

    # Accepts a code or a recovery code. Each works once. Five wrong answers lock the credential for LOCKOUT.
    def verify!(code)
      entered = code.to_s.strip.downcase
      attempt { entered.match?(/\A\d{6}\z/) ? verify_code(entered) : use_recovery_code(entered) }
    end

    def recovery_codes_left = recovery_code_digests.size

    private

    # An expired lock resets the count, so the next wrong code does not lock it again at once.
    def attempt
      reset_failures if locked_until.present? && !locked?
      return false if locked?

      ok = yield
      ok ? reset_failures : record_failure
      ok
    end

    # Claims the code's time step in one UPDATE, so the same code cannot be used twice, even by two requests at once.
    def verify_code(code)
      step = ROTP::TOTP.new(totp_secret, issuer: ISSUER).verify(code.to_s.strip, drift_behind: DRIFT_SECONDS)
      return false unless step

      self.class.where(id: id).where("last_used_step IS NULL OR last_used_step < ?", step)
          .update_all(last_used_step: step, updated_at: Time.current) > 0
    end

    def use_recovery_code(code)
      wanted = digest(code)
      self.class.where(id: id).where("? = ANY(recovery_code_digests)", wanted)
          .update_all([ "recovery_code_digests = array_remove(recovery_code_digests, ?), updated_at = ?", wanted, Time.current ]) > 0
    end

    def record_failure
      self.class.where(id: id).update_all([
        "failed_attempts = failed_attempts + 1, " \
        "locked_until = CASE WHEN failed_attempts + 1 >= ? THEN ? ELSE locked_until END, updated_at = ?",
        MAX_FAILED_ATTEMPTS, LOCKOUT.from_now, Time.current
      ])
    end

    def reset_failures
      self.class.where(id: id).update_all(failed_attempts: 0, locked_until: nil, updated_at: Time.current)
    end

    # Recovery codes have about 50 bits of entropy, so an HMAC keyed by the app secret is enough.
    def digest(code) = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, code.to_s.strip.downcase)
  end
end

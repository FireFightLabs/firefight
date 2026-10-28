# A sign-in to an AI subscription the person has waiting, which the card's dialog shows: the code to enter, or where to
# sign in and that the address the browser lands on comes back here.
class SubscriptionSignInSerializer < BaseSerializer
  object_as :sign_in

  type :string
  def id = sign_in.id

  type :string
  def name = sign_in.subscription_definition&.name.to_s

  type :boolean
  def device = sign_in.user_code.present?

  type :string
  def url = sign_in.url

  # The site the person goes to, which the dialog names.
  type :string
  def host = URI.parse(sign_in.url).host.to_s.delete_prefix("www.")

  type :string, optional: true
  def user_code = sign_in.user_code

  type :string, optional: true
  def expires_at = sign_in.expires_at&.iso8601

  type :boolean
  def reconnecting = sign_in.reconnecting?
end

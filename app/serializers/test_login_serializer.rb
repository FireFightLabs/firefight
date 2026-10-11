# A saved test login as its settings row shows it. The password is never part of it, only when it was saved. The username
# and login page go only to whoever manages integrations (manage), everyone else sees the site and when it was saved.
class TestLoginSerializer < BaseSerializer
  object_as :login

  attributes(
    id: { type: :string },
    name: { type: :string },
    site_url: { type: :string },
    password_hint: { type: :string }
  )

  type :string, optional: true
  def username = (login.username if options[:manage])

  type :string, optional: true
  def login_url = (login.login_url if options[:manage])
end

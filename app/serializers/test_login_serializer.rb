# A saved test login as its settings row shows it. The password is never part of it, only when it was saved.
class TestLoginSerializer < BaseSerializer
  object_as :login

  attributes(
    id: { type: :string },
    name: { type: :string },
    site_url: { type: :string },
    username: { type: :string },
    password_hint: { type: :string }
  )

  type :string, optional: true
  def login_url = login.login_url
end

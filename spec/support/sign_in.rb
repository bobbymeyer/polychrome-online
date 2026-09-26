# frozen_string_literal: true

# Accounts in request specs. Every request spec signs in as the first account
# (the admin) unless it is tagged `signed_out: true` or signs in as someone
# else with #sign_in_as.
module SignIn
  PASSWORD = "correct horse battery"

  def make_user(name = "Player #{SecureRandom.hex(3)}", admin: false)
    User.create!(name: name, email_address: "#{name.parameterize}-#{SecureRandom.hex(3)}@example.com",
                 password: PASSWORD).tap { |u| u.update!(admin: true) if admin && !u.admin? }
  end

  def sign_in_as(user)
    post session_path, params: { email_address: user.email_address, password: PASSWORD }
    user
  end

  def sign_out
    delete session_path
  end
end

RSpec.configure do |config|
  config.include SignIn, type: :request
  config.before(type: :request) do |example|
    @admin = sign_in_as(make_user("Admin")) unless example.metadata[:signed_out]
  end
end

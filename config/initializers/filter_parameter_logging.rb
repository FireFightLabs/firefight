Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :access_token, :refresh_token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]

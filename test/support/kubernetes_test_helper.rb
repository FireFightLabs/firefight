# A cluster CA the Kubernetes tests trust, made fresh so no key is kept in the repository.
module KubernetesTestHelper
  def kubernetes_ca_pem
    key = OpenSSL::PKey::EC.generate("prime256v1")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=kubernetes")
    cert.public_key = key
    cert.not_before = Time.current
    cert.not_after = 1.day.from_now
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    cert.to_pem
  end
end

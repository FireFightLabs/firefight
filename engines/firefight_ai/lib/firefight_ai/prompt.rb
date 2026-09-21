require "digest"

module FirefightAi
  # A prompt's version is a digest of its own wording, so an edited prompt cannot keep the old version and two
  # different wordings cannot share one. Per run values stay out of it, since they change every call.
  module Prompt
    LENGTH = 12

    def self.version(text)
      Digest::SHA256.hexdigest(text.to_s)[0, LENGTH]
    end
  end
end

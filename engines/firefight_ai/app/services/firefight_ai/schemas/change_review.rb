module FirefightAi
  module Schemas
    class ChangeReview < ::Schematist::Schema
      description "Whether a code change does what the person asked, what is wrong with it, and what it assumes that nothing verified"

      boolean :does_what_was_asked, description: "True when the change does what the person asked, with their corrections, and nothing in it breaks what it touches. A finding that does not stop that, such as a missing test, can stand beside true"
      array :findings, description: "Each problem with the change, one plain sentence each naming the file, such as a value sent where the other system never reads it. Empty when there are none", of: :string
      array :unverified, description: "Each assumption the change makes about another system, a library or the person's intent that neither the evidence nor the checks verify, one plain sentence each. Empty when there are none", of: :string
      string :summary, description: "One plain sentence on what the change does"
    end
  end
end

module FirefightAi
  module Schemas
    class ThreadAnswer < ::Schematist::Schema
      description "Halon's answer to a person's reply on a thread its review started"

      string :answer, description: "What Halon replies, in two to five short plain sentences that answer what the person said, naming the file or the value"
      boolean :withdraw, description: "True only when the person showed the finding is wrong, such as code that already handles it or a misread of how something behaves. False when the finding still holds or the person only said they will fix it later"
      string :reason, description: "When withdraw is true, one plain sentence saying why the finding was wrong. Empty otherwise"
    end
  end
end

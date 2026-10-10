module FirefightAi
  # Seen in a real chat, asked for a value in a production database, Halon guessed table and column names query after
  # query while the application's schema sat in its repository, read from a replica first, and said nothing of two reads
  # that waited 35 seconds each for no answer. The three hold in a chat and a run.
  module DatabaseRule
    SCHEMA_RULE = "Before writing a query against an application's own tables, read their names and columns from the " \
                  "application's repository on the connected code host, such as db/schema.rb, db/structure.sql, " \
                  "prisma/schema.prisma, its models or its migrations, found with code_search or list_files. Never guess " \
                  "a table or column name. When no repository you can read holds them, read the database's own schema " \
                  "for those tables first, through the provider's schema tool or its catalog, then write the query.".freeze

    REPLICA_RULE = "Read a database's primary first, since it is current. Read from a replica only as a fallback, when " \
                   "the primary was slow or refused, and then say the answer came from a replica, which may lag behind it.".freeze

    SLOW_RULE = "When a provider did not answer in time, say so in your answer, with what you did instead, such as reading " \
                "it again or getting it another way, so the person knows why it took long or what is missing.".freeze
  end
end

# Builds a real git repository in a tempdir for clone-manager and code-tool
# tests: two commits by distinct authors so blame has history, a nested file
# for path handling, and a secrets-shaped file for denylist coverage. Tests
# stub CloneManager.remote_url to point at the returned path; git clones
# happily from a local directory.
module FixtureRepo
  FIRST_AUTHOR = [ "Ada Payments", "ada@example.com" ].freeze
  SECOND_AUTHOR = [ "Grace Retries", "grace@example.com" ].freeze

  def self.create!
    dir = Dir.mktmpdir("fixture-repo")
    run(dir, "init", "--quiet", "--initial-branch=main")

    File.write(File.join(dir, "payment.rb"), <<~RUBY)
      class Payment
        def charge(amount)
          amount
        end
      end
    RUBY
    FileUtils.mkdir_p(File.join(dir, "config"))
    File.write(File.join(dir, "config/service.yml"), "retries: 1\n")
    File.write(File.join(dir, ".env"), "SECRET=shhh\n")
    commit(dir, "Add payment charging", FIRST_AUTHOR)

    File.write(File.join(dir, "payment.rb"), <<~RUBY)
      class Payment
        def charge(amount)
          retry_budget(amount)
        end

        def retry_budget(amount)
          amount * 2
        end
      end
    RUBY
    commit(dir, "Tighten retry budget", SECOND_AUTHOR)

    dir
  end

  def self.add_commit(dir, filename, content, message)
    File.write(File.join(dir, filename), content)
    commit(dir, message, SECOND_AUTHOR)
  end

  def self.commit(dir, message, author)
    run(dir, "add", "-A")
    run(dir, "-c", "user.name=#{author[0]}", "-c", "user.email=#{author[1]}",
        "commit", "--quiet", "-m", message)
  end

  def self.head_sha(dir)
    output, = Open3.capture2("git", "-C", dir, "rev-parse", "HEAD")
    output.strip
  end

  def self.run(dir, *args)
    _, stderr, status = Open3.capture3("git", "-C", dir, *args)
    raise "fixture repo git #{args.first} failed: #{stderr}" unless status.success?
  end
end

# The one way git in the sandbox reaches the code host: a smart HTTP endpoint the box reaches with its code change
# session's token, like the model proxy, which passes requests on with the connection's own credential, so the code
# host's token never enters the box. Fetching is reading the session's repository. A push is let through only when every
# ref it updates is the session's own branch, created, moved or forced, never deleted, and never a tag, the base or any
# other branch. Only the push's ref update commands (the pkt-line lines before its flush) are read. The pack after them
# is streamed on as it came and never unpacked here.
class Integrations::GitGate
  class Refused < StandardError; end

  UPLOAD = "git-upload-pack".freeze
  RECEIVE = "git-receive-pack".freeze
  SERVICES = [ UPLOAD, RECEIVE ].freeze
  ZERO = /\A0+\z/
  OBJECT_ID = /\A(\h{40}|\h{64})\z/
  BRANCHES = "refs/heads/".freeze
  # A push's commands are a few lines, so a header past this is not one.
  MAX_COMMANDS_BYTES = 64.kilobytes
  # What a fetch asks for is a list of commits, and a push of one change is far below a pack this large.
  MAX_UPLOAD_BYTES = 10.megabytes
  MAX_PUSH_BYTES = 200.megabytes

  Command = Data.define(:old, :new, :ref)

  def initialize(session)
    @session = session
  end

  attr_reader :session

  # The refs the code host advertises for a service, as git asks before it fetches or pushes.
  def advertise(service, headers:, &)
    raise Refused, "No git service called #{service}." unless SERVICES.include?(service)

    Integrations::GitHttp.forward(remote, repository, "info/refs?service=#{service}", method: :get, headers: headers, &)
  end

  def upload(body, length:, headers:, &)
    Integrations::GitHttp.forward(remote, repository, UPLOAD, method: :post, body: body, length: length, headers: headers, &)
  end

  # Reads the commands, refuses any it does not allow, then passes the commands and the pack behind them on unread.
  def receive(body, length:, headers:, &)
    raise Refused, "A push must not be compressed, so its commands can be read." if headers["Content-Encoding"].present?

    commands, taken = self.class.commands(body)
    refusal = self.class.refusal(commands, @session.git_branch)
    raise Refused, refusal if refusal

    Rails.logger.info({ event: "code_agent.git_push", code_agent_session_id: @session.id, refs: commands.map(&:ref) }.to_json)
    Integrations::GitHttp.forward(remote, repository, RECEIVE, method: :post, body: Joined.new(taken, body), length: length, headers: headers, &)
  end

  # The ref update commands at the head of a push, and the bytes they took, read one pkt-line at a time up to the flush.
  def self.commands(body)
    taken = +"".b
    commands = []
    loop do
      size = body.read(4).to_s
      taken << size
      raise Refused, "The push ended before its commands did." unless size.match?(/\A\h{4}\z/)

      length = size.to_i(16)
      break if length.zero?
      raise Refused, "The push's commands are not ones git sends." if length < 5 || taken.bytesize + length > MAX_COMMANDS_BYTES

      line = body.read(length - 4).to_s.b
      taken << line
      commands << command(line)
    end
    [ commands, taken ]
  end

  def self.command(line)
    old, new, ref = line.split("\0", 2).first.to_s.chomp.split(" ", 3)
    raise Refused, "The push's commands are not ones git sends." unless old.to_s.match?(OBJECT_ID) && new.to_s.match?(OBJECT_ID) && ref.present?

    Command.new(old: old, new: new, ref: ref)
  end
  private_class_method :command

  # Why a push is refused, or nil: every ref it updates must be the session's own branch, and none may be deleted.
  def self.refusal(commands, branch)
    return "This code change has no branch it may push to." if branch.blank?
    return "The push updates nothing." if commands.empty?

    commands.each do |command|
      return "A code change never deletes a branch or a tag (#{command.ref})." if command.new.match?(ZERO)
      return "A code change never pushes tags (#{command.ref})." if command.ref.start_with?("refs/tags/")
      return "A code change pushes only to its own branch, #{branch}, never #{command.ref.delete_prefix(BRANCHES)}." unless command.ref == "#{BRANCHES}#{branch}"
    end
    nil
  end

  private

  def repository = @session.repository

  # The connection's own git address and credential, through the code host's contract.
  def remote
    row = @session.integration_environment
    raise Refused, "This code change has no code host connection to reach." unless row

    pack = Integrations::NativePack.fetch!(row.integration)
    raise Refused, "#{row.integration.name} cannot be reached with git through Firefight." unless pack.respond_to?(:code_remote)

    found = pack.code_remote(row)
    raise Refused, "#{row.integration.name} is reached through a checked address, which git through Firefight does not support yet." if found.options.any?

    found
  end

  # The commands already read, then the rest of the request as it comes, for a request body read in pieces.
  class Joined
    def initialize(head, rest)
      @head = StringIO.new(head)
      @rest = rest
    end

    # As IO#read: everything without a length, otherwise at most length bytes, nil once both are spent.
    def read(length = nil, buffer = nil)
      data = length.nil? ? "#{@head.read}#{@rest.read}".b : (@head.read(length) || @rest.read(length))
      return data if data.nil? || buffer.nil?

      buffer.replace(data)
    end
  end
end

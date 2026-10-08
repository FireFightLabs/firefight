require "test_helper"

# What the git gate lets through to the code host: only the session's own branch, created, moved or forced, never a
# delete, a tag, the base or any other branch, read from the push's commands alone.
class Integrations::GitGateTest < ActiveSupport::TestCase
  ZERO = "0" * 40
  OLD = "a" * 40
  NEW = "b" * 40

  test "a push's commands are read up to its flush, and the pack behind them is left unread" do
    pack = "PACK\x00\x00\x00\x02not a pack anyone parses".b
    body = StringIO.new(pkt("#{OLD} #{NEW} refs/heads/halon/fix-1\0report-status side-band-64k\n") + "0000" + pack)

    commands, taken = Integrations::GitGate.commands(body)

    assert_equal [ Integrations::GitGate::Command.new(old: OLD, new: NEW, ref: "refs/heads/halon/fix-1") ], commands
    assert_equal pack, body.read, "nothing past the commands was read"
    assert taken.end_with?("0000")
  end

  test "creating, moving and forcing the session's own branch pass" do
    [ [ ZERO, NEW ], [ OLD, NEW ], [ NEW, OLD ] ].each do |old, new|
      assert_nil refusal([ command(old, new, "refs/heads/halon/fix-1") ])
    end
  end

  test "a push to the base, to another branch, of a tag, or that deletes, is refused" do
    assert_equal "A code change pushes only to its own branch, halon/fix-1, never main.", refusal([ command(OLD, NEW, "refs/heads/main") ])
    assert_equal "A code change pushes only to its own branch, halon/fix-1, never halon/fix-2.", refusal([ command(OLD, NEW, "refs/heads/halon/fix-2") ])
    assert_equal "A code change never pushes tags (refs/tags/v1).", refusal([ command(ZERO, NEW, "refs/tags/v1") ])
    assert_equal "A code change never deletes a branch or a tag (refs/heads/halon/fix-1).", refusal([ command(OLD, ZERO, "refs/heads/halon/fix-1") ])
    assert_match "never main", refusal([ command(OLD, NEW, "refs/heads/halon/fix-1"), command(OLD, NEW, "refs/heads/main") ]), "one bad ref refuses the push"
    assert_equal "This code change has no branch it may push to.", Integrations::GitGate.refusal([ command(OLD, NEW, "refs/heads/x") ], nil)
  end

  test "anything that is not a ref update command is refused" do
    assert_raises(Integrations::GitGate::Refused) { Integrations::GitGate.commands(StringIO.new(pkt("push-cert\0push-options\n") + "0000")) }
    assert_raises(Integrations::GitGate::Refused) { Integrations::GitGate.commands(StringIO.new("zzzz")) }
    assert_raises(Integrations::GitGate::Refused) { Integrations::GitGate.commands(StringIO.new(pkt("#{OLD} #{NEW} refs/heads/x\n"))) }
  end

  private

  def refusal(commands) = Integrations::GitGate.refusal(commands, "halon/fix-1")

  def command(old, new, ref) = Integrations::GitGate::Command.new(old: old, new: new, ref: ref)

  def pkt(line) = format("%04x", line.bytesize + 4) + line
end

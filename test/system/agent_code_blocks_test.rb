require "application_system_test_case"

# Code in Halon's answers is highlighted in the language its fence names, or the one it most likely is when the fence
# names none, plain when neither is known, and a long line scrolls inside its block on a phone.
class AgentCodeBlocksTest < ApplicationSystemTestCase
  ANSWER = <<~'MARKDOWN'.freeze
    Ruby:

    ```ruby
    class Pool
      SIZE = 10 # the old value was 2
      def checkout = connections.first
    end
    ```

    TypeScript:

    ```ts
    export function retries(count: number): string[] {
      return Array.from({ length: count }, (_, index) => `attempt ${index}`)
    }
    ```

    YAML:

    ```yaml
    on:
      push:
        tags: ["v*"]
    env:
      RUN_NAME: release-${{ github.ref_name }}
    ```

    SQL:

    ```sql
    SELECT id, state FROM pg_stat_activity WHERE state = 'idle in transaction' AND query_start < now() - interval '5 minutes';
    ```

    Bash:

    ```bash
    curl -fsS -X POST "$NORTHFLANK_WEBHOOK" -H 'Content-Type: application/json' -d "{\"name\": \"$RUN_NAME\"}"
    ```

    No language named:

    ```
    def deliver(update)
      return if update.nil?
      Rails.logger.info("delivered #{update.id}")
    end
    ```

    Plain words in a block:

    ```
    nothing here is code at all
    ```

    Inline `code` stays a chip.
  MARKDOWN

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @conversation.ask!("Show me the fixes")
    @conversation.note!(ANSWER)
    @conversation.reply_delivered!
  end

  test "each fenced block is highlighted in its language, a block without one in the language it most likely is, and plain words stay plain" do
    visit agent_chat_path(@conversation)

    blocks = all("pre", minimum: 7)
    assert blocks[0].has_css?("code.hljs .hljs-keyword", text: "class"), "ruby"
    assert blocks[1].has_css?("code.hljs .hljs-keyword", text: "export"), "typescript"
    assert blocks[2].has_css?("code.hljs .hljs-attr", text: "tags"), "yaml"
    assert blocks[3].has_css?("code.hljs .hljs-keyword", text: "SELECT"), "sql"
    assert blocks[4].has_css?("code.hljs .hljs-string", text: "Content-Type"), "bash"
    assert blocks[5].has_css?("code.hljs .hljs-keyword", text: "def"), "a block naming no language is guessed"
    assert blocks[6].has_no_css?("code.hljs"), "plain words are not coloured"
    assert_equal "nothing here is code at all", blocks[6].text
    assert_selector "p code", text: "code"
    page.save_screenshot(Rails.root.join("tmp/screenshots/code-blocks-desktop.png"))

    page.current_window.resize_to(390, 844)
    visit agent_chat_path(@conversation)
    assert_selector "code.hljs", minimum: 6
    sql = all("pre")[3]
    assert_operator page.evaluate_script("arguments[0].scrollWidth > arguments[0].clientWidth", sql), :==, true
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390, "the page itself never scrolls sideways"
    sql.scroll_to(:center)
    page.save_screenshot(Rails.root.join("tmp/screenshots/code-blocks-phone.png"))
  end
end

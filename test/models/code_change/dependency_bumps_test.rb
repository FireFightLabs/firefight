require "test_helper"

class CodeChange::DependencyBumpsTest < ActiveSupport::TestCase
  test "a lockfile diff reads as the versions that moved, not as the lines that changed" do
    patch = "@@\n-    pg (1.4.0)\n+    pg (1.5.0)\n     rack (3.0.0)\n+    redis (5.0.0)\n-    oj (3.1.0)\n"

    bumps = CodeChange::DependencyBumps.from("Gemfile.lock", patch).map(&:to_s)

    assert_equal [ "pg 1.4.0 to 1.5.0", "oj removed (was 3.1.0)", "redis added at 5.0.0" ].sort, bumps.sort
  end

  test "a manifest in a subfolder is read too" do
    patch = "@@\n-    \"react\": \"^18.2.0\",\n+    \"react\": \"^18.3.1\",\n"

    assert_equal [ "react ^18.2.0 to ^18.3.1" ], CodeChange::DependencyBumps.from("web/package.json", patch).map(&:to_s)
  end

  test "a format it does not read gives no versions rather than a wrong one" do
    assert_empty CodeChange::DependencyBumps.from("yarn.lock", "@@\n-react@18.2.0\n+react@18.3.1\n")
  end
end

require "test_helper"

module Integrations
  module Packs
    class Github
      class InfrastructureTest < ActiveSupport::TestCase
        setup do
          @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          GithubApp.stubs(:installation_token).returns("ghs_token")
          repositories([ repo("acme/infra"), repo("acme/old", "archived" => true), repo("acme/fork", "fork" => true), repo("acme/empty", "size" => 0),
                         repo("acme/cdk") ])
          tree("acme/infra", [
            blob("cloudflare/dns.tf"), blob("README.md"), blob("node_modules/x/main.tf"), blob("huge.tf", size: 500_000),
            blob("pulumi/Pulumi.yaml"), blob("pulumi/Pulumi.prod.yaml"), blob("pulumi/index.ts"), blob("charts/web/Chart.yaml"),
            blob("charts/web/values.yaml"), blob("k8s/deployment.yaml"), blob("k8s/notes.yaml"), blob("k8s/secret.yaml"),
            blob("workers/api/wrangler.toml"), blob("src/app.ts")
          ])
          tree("acme/cdk", [ blob("cdk.json"), blob("bin/app.ts"), blob("src/handler.ts"), blob(".github/workflows/ci.yml") ])
          contents("acme/infra",
                   "cloudflare/dns.tf" => %(resource "cloudflare_record" "app" { name = "app.acme.com" }),
                   "pulumi/Pulumi.yaml" => "name: infra", "pulumi/index.ts" => "new northflank.Service('web')",
                   "charts/web/Chart.yaml" => "name: web", "charts/web/values.yaml" => "replicas: 2",
                   "k8s/deployment.yaml" => "kind: Deployment\nmetadata:\n  name: web", "k8s/notes.yaml" => "todo: later",
                   "k8s/secret.yaml" => "kind: Secret\ndata:\n  password: aHVudGVyMg==", "workers/api/wrangler.toml" => %(name = "edge-api"))
          contents("acme/cdk", "cdk.json" => "{}", "bin/app.ts" => "new Stack()")
        end

        test "only infrastructure files are read, each labelled with the tool that defines it, and never a secret or a stack's config" do
          snapshot = Github.new(@integration).map_of(@row)

          read = snapshot.code_files.map { |file| [ file.repository, file.path, file.tool ] }
          assert_equal [ [ "acme/infra", "cloudflare/dns.tf", "Terraform" ], [ "acme/infra", "pulumi/Pulumi.yaml", "Pulumi" ],
                         [ "acme/infra", "pulumi/index.ts", "Pulumi" ], [ "acme/infra", "charts/web/Chart.yaml", "Helm" ],
                         [ "acme/infra", "charts/web/values.yaml", "Helm" ], [ "acme/infra", "k8s/deployment.yaml", "Kubernetes" ],
                         [ "acme/infra", "workers/api/wrangler.toml", "Wrangler" ],
                         [ "acme/cdk", "cdk.json", "CDK" ], [ "acme/cdk", "bin/app.ts", "CDK" ] ], read
          assert_equal "https://github.com/acme/infra/blob/main/cloudflare/dns.tf", snapshot.code_files.first.url
          assert_equal %w[acme/infra acme/old acme/fork acme/empty acme/cdk], snapshot.resources.map(&:external_id)
        end

        test "a repository with a file left unread is not read in full, and says why in one line" do
          snapshot = Github.new(@integration).map_of(@row)

          assert_equal %w[acme/empty acme/cdk], snapshot.code_read
          assert_equal [ "1 infrastructure file in acme/infra is over 200 KB and was not read." ], snapshot.gaps
        end

        test "a tree too large to list, or files that cannot be read, are gaps, one per repository" do
          tree("acme/infra", [ blob("a.tf"), blob("b.tf") ], truncated: true)
          GithubApp.stubs(:get).with("/repos/acme/infra/git/blobs/a.tf", token: "ghs_token").raises(GithubApp::Error, "GitHub: Not Found")
          GithubApp.stubs(:get).with("/repos/acme/infra/git/blobs/b.tf", token: "ghs_token").raises(GithubApp::Error, "GitHub: Not Found")

          gaps = Github.new(@integration).map_of(@row).gaps

          assert_includes gaps, "acme/infra is too large to list in full, so some of its infrastructure files may be missing."
          assert_includes gaps, "2 infrastructure files in acme/infra could not be read: GitHub: Not Found"
        end

        test "a rate limit stops the search, and what was not searched keeps its suggestions" do
          GithubApp.stubs(:get).with("/repos/acme/infra/git/trees/main?recursive=1", token: "ghs_token").raises(GithubApp::RateLimited, "GitHub: API rate limit exceeded")

          snapshot = Github.new(@integration).map_of(@row)

          assert_empty snapshot.code_files
          assert_empty snapshot.code_read
          assert_equal [ "Not every repository was searched for infrastructure files, since GitHub's rate limit was reached after 0 of 3 repositories." ], snapshot.gaps
        end

        test "repositories past what is listed are not taken as gone" do
          GithubApp.stubs(:get).with("/installation/repositories?per_page=100&page=1", token: "ghs_token")
                   .returns("total_count" => 1500, "repositories" => [ repo("acme/infra") ])
          GithubApp.stubs(:get).with { |path, **| path.start_with?("/installation/repositories?per_page=100&page=") && !path.end_with?("page=1") }
                   .returns("total_count" => 1500, "repositories" => [])

          snapshot = Github.new(@integration).map_of(@row)

          assert_equal [ ResourceMap::KIND_REPOSITORY ], snapshot.unread_kinds
          assert_includes snapshot.gaps, "Only the first 1 of 1500 repositories were listed."
        end

        private

        def repo(name, extra = {})
          { "full_name" => name, "default_branch" => "main", "html_url" => "https://github.com/#{name}", "size" => 10 }.merge(extra)
        end

        def repositories(listed)
          GithubApp.stubs(:get).with("/installation/repositories?per_page=100&page=1", token: "ghs_token").returns("total_count" => listed.size, "repositories" => listed)
        end

        def tree(name, entries, truncated: false)
          GithubApp.stubs(:get).with("/repos/#{name}/git/trees/main?recursive=1", token: "ghs_token").returns("tree" => entries, "truncated" => truncated)
        end

        def contents(name, files)
          files.each do |path, text|
            GithubApp.stubs(:get).with("/repos/#{name}/git/blobs/#{path.tr('/', '-')}", token: "ghs_token")
                     .returns("encoding" => "base64", "content" => Base64.encode64(text))
          end
        end

        def blob(path, size: 100) = { "type" => "blob", "path" => path, "sha" => path.tr("/", "-"), "size" => size }
      end
    end
  end
end

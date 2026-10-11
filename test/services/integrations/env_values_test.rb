require "test_helper"

module Integrations
  # A service's or app's environment variables are often its secrets, so every general read that can answer one, as each
  # pack writes its answer, keeps the variables' names and never their values.
  class EnvValuesTest < ActiveSupport::TestCase
    VALUE = "plain-value-4815".freeze

    test "Google Cloud: a Cloud Run service, revision and job, a function and a build keep their variables' names only" do
      service = { "name" => "projects/p/locations/l/services/web",
                  "template" => { "containers" => [ { "image" => "gcr.io/p/web", "env" => [ { "name" => "STRIPE_KEY", "value" => VALUE },
                                                                                          { "name" => "DB", "valueSource" => { "secretKeyRef" => { "secret" => "db", "version" => "latest" } } } ] } ] } }
      revision = { "name" => "web-00042", "containers" => [ { "env" => [ { "name" => "STRIPE_KEY", "value" => VALUE } ] } ] }
      job = { "template" => { "template" => { "containers" => [ { "env" => [ { "name" => "STRIPE_KEY", "value" => VALUE } ] } ] } } }
      function = { "name" => "fn", "serviceConfig" => { "environmentVariables" => { "STRIPE_KEY" => VALUE }, "secretEnvironmentVariables" => [ { "key" => "DB", "secret" => "db" } ] },
                   "buildConfig" => { "environmentVariables" => { "NPM_TOKEN" => VALUE } } }
      function_v1 = { "name" => "fn", "environmentVariables" => { "STRIPE_KEY" => VALUE }, "buildEnvironmentVariables" => { "NPM_TOKEN" => VALUE } }
      build = { "id" => "b-1", "options" => { "env" => [ "STRIPE_KEY=#{VALUE}" ] }, "steps" => [ { "name" => "gcr.io/cloud-builders/npm", "env" => [ "NPM_TOKEN=#{VALUE}" ] } ] }
      app_engine = { "id" => "v1", "envVariables" => { "STRIPE_KEY" => VALUE } }

      [ service, revision, job, function, function_v1, build, app_engine ].each do |answer|
        text = ApiReads.answer("Google Cloud", "run GET /x", ReadGuards::GoogleCloud.hidden(answer))
        assert_not_includes text, VALUE, answer.keys.inspect
      end
      text = ApiReads.answer("Google Cloud", "run GET /x", ReadGuards::GoogleCloud.hidden(service))
      assert_includes text, "STRIPE_KEY"
      assert_includes text, "gcr.io/p/web"
      assert_includes ApiReads.answer("Google Cloud", "x", ReadGuards::GoogleCloud.hidden(function)), "NPM_TOKEN"
    end

    test "Azure: a Container App's env, its secrets and a site's appSettings keep their names only" do
      app = { "properties" => { "template" => { "containers" => [ { "env" => [ { "name" => "STRIPE_KEY", "value" => VALUE }, { "name" => "DB", "secretRef" => "db" } ] } ] },
                                "configuration" => { "secrets" => [ { "name" => "db", "value" => VALUE } ] } } }
      site = { "properties" => { "siteConfig" => { "appSettings" => [ { "name" => "STRIPE_KEY", "value" => VALUE } ], "linuxFxVersion" => "NODE|20" } } }

      [ app, site ].each do |answer|
        text = ApiReads.answer("Azure", "GET /x", ReadGuards::Azure.hidden(answer))
        assert_not_includes text, VALUE
        assert_includes text, "STRIPE_KEY"
      end
      assert_includes ApiReads.answer("Azure", "GET /x", ReadGuards::Azure.hidden(site)), "NODE|20"
    end

    test "AWS: a task definition's, a function's, a build project's and an App Runner service's variables keep their names only" do
      answers = [
        { task_definition: { container_definitions: [ { name: "web", environment: [ { name: "STRIPE_KEY", value: VALUE } ] } ] } },
        { configuration: { function_name: "fn", environment: { variables: { "STRIPE_KEY" => VALUE } } } },
        { projects: [ { name: "build", environment: { environment_variables: [ { name: "STRIPE_KEY", value: VALUE, type: "PLAINTEXT" } ] } } ] },
        { service: { source_configuration: { image_repository: { image_configuration: { runtime_environment_variables: { "STRIPE_KEY" => VALUE } } } } } }
      ]

      answers.each do |answer|
        text = ApiReads.answer("AWS", "ecs X", ReadGuards::Aws.hidden(answer))
        assert_not_includes text, VALUE, answer.keys.inspect
        assert_includes text, "STRIPE_KEY"
      end
    end

    test "every path provider's service or app read keeps its variables' names only" do
      answers = {
        "Kubernetes" => { "spec" => { "containers" => [ { "name" => "web", "env" => [ { "name" => "STRIPE_KEY", "value" => VALUE } ] } ] } },
        "Vercel" => { "name" => "shop", "env" => [ { "key" => "STRIPE_KEY", "value" => VALUE, "type" => "plain" } ] },
        "Netlify" => { "name" => "shop", "build_settings" => { "env" => { "STRIPE_KEY" => VALUE } } },
        "DigitalOcean" => { "app" => { "spec" => { "services" => [ { "name" => "web", "envs" => [ { "key" => "STRIPE_KEY", "value" => VALUE, "scope" => "RUN_TIME" } ] } ] } } },
        "Fly.io" => { "id" => "m-1", "config" => { "env" => { "STRIPE_KEY" => VALUE }, "image" => "registry.fly.io/web" } },
        "Render" => { "id" => "srv-1", "envVars" => [ { "key" => "STRIPE_KEY", "value" => VALUE } ] },
        "Trigger.dev" => { "id" => "dep-1", "environmentVariables" => { "STRIPE_KEY" => VALUE } }
      }

      answers.each do |provider, answer|
        text = ApiReads.answer(provider, "GET /x", answer)
        assert_not_includes text, VALUE, provider
        assert_includes text, "STRIPE_KEY", provider
      end
    end
  end
end

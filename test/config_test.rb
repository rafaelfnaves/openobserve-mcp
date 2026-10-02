# frozen_string_literal: true

require 'test_helper'
require 'pp'

class ConfigTest < Minitest::Test
  Config = ObservabilityMcp::Config

  def test_discovers_environments_and_strips_trailing_slash
    config = Config.new(ENV_VARS.merge('OO_PROD_URL' => 'https://prod.test', 'OO_PROD_USER' => 'u'))

    assert_equal %w[prod staging], config.environments.keys
    assert_equal 'https://oo.test', config.environments['staging'].url
    assert_equal ['OO_PROD_PASSWORD'], config.environments['prod'].missing_vars
  end

  def test_single_environment_is_the_default
    config = Config.new(ENV_VARS)

    assert_equal 'staging', config.environment.name
    assert_equal 'serverless', config.org(config.environment)
    assert_equal 'other', config.org(config.environment, 'other')
  end

  def test_explains_missing_or_unknown_environments
    config = Config.new(ENV_VARS.merge('OO_PROD_URL' => 'https://prod.test'))

    assert_match(/`env` is required. Configured environments: prod, staging/, assert_raises(ObservabilityMcp::Error) { config.environment }.message)
    assert_match(/Unknown env 'qa'/, assert_raises(ObservabilityMcp::Error) { config.environment('qa') }.message)
    assert_match(/missing OO_PROD_USER, OO_PROD_PASSWORD/, assert_raises(ObservabilityMcp::Error) { config.environment('prod') }.message)
  end

  def test_rejects_unusable_urls
    {
      'oo.example.com' => /must be an absolute http\(s\) URL/,
      'https://exa mple.com' => /not a valid URL/,
      'http://oo.example.com' => /plain http/
    }.each do |url, message|
      config = Config.new(ENV_VARS.merge('OO_STAGING_URL' => url))
      assert_match message, assert_raises(ObservabilityMcp::Error) { config.environment }.message
    end
    assert Config.new(ENV_VARS.merge('OO_STAGING_URL' => 'http://localhost:5080')).environment
    assert Config.new(ENV_VARS.merge('OO_STAGING_URL' => 'http://oo.lan', 'OO_ALLOW_INSECURE_HTTP' => 'true')).environment
  end

  def test_environment_names_may_contain_underscores
    config = Config.new(ENV_VARS.merge('OO_PROD_EU_URL' => 'https://eu.test', 'OO_PROD_EU_USER' => 'u', 'OO_PROD_EU_PASSWORD' => 'p'))

    assert_equal 'https://eu.test', config.environment('prod_eu').url
  end

  def test_timeout_parsing_is_lenient
    assert_equal 45.0, Config.new(ENV_VARS.merge('OO_TIMEOUT' => '45s')).timeout
    _, stderr = capture_io { assert_equal 30.0, Config.new(ENV_VARS.merge('OO_TIMEOUT' => 'soon')).timeout }
    assert_match(/ignoring invalid OO_TIMEOUT/, stderr)
  end

  def test_password_never_appears_in_inspect_or_pp
    runtime = build_runtime
    target = runtime.target
    dumps = [target.environment.inspect, target.environment.to_s, target.inspect, target.client.inspect,
             runtime.inspect, PP.pp(target, +'')]

    dumps.each { refute_includes it, 'secret' }
    assert_includes target.environment.inspect, 'password=[REDACTED]'
  end

  def test_requires_an_org_when_no_default_exists
    config = Config.new(ENV_VARS.except('OO_STAGING_ORG'))

    assert_match(/`org` is required/, assert_raises(ObservabilityMcp::Error) { config.org(config.environment) }.message)
    assert_equal 'web', Config.new(ENV_VARS.except('OO_STAGING_ORG').merge('OO_DEFAULT_ORG' => 'web')).then { it.org(it.environment) }
  end
end

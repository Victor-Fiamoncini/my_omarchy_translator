# frozen_string_literal: true

require_relative 'test_helper'

class ConfigTest < Minitest::Test
  def with_config(env = {})
    Dir.mktmpdir do |dir|
      yield OmarchyTranslator::Config.new(env: { 'XDG_CONFIG_HOME' => "#{dir}/config",
                                                 'XDG_STATE_HOME' => "#{dir}/state",
                                                 'CLAUDE_CODE_BIN' => '/nonexistent/claude' }.merge(env))
    end
  end

  def write(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def test_reads_key_from_env_file
    with_config do |config|
      write(config.env_path, "# comment\n\nexport DEEPL_AUTH_KEY=\"secret:fx\"\n")

      assert_equal 'secret:fx', config.setting('DEEPL_AUTH_KEY')
    end
  end

  def test_env_file_ignores_lines_without_a_value
    with_config do |config|
      write(config.env_path, "JUNK\nDEEPL_AUTH_KEY=secret\n")

      assert_nil config.setting('JUNK')
      assert_equal 'secret', config.setting('DEEPL_AUTH_KEY')
    end
  end

  def test_env_file_quotes_must_match
    with_config do |config|
      write(config.env_path, "DEEPL_AUTH_KEY='single'\nOTHER=\"mismatched'\n")

      assert_equal 'single', config.setting('DEEPL_AUTH_KEY')
    end
  end

  def test_environment_key_wins
    with_config('DEEPL_AUTH_KEY' => 'from-env') do |config|
      assert_equal 'from-env', config.setting('DEEPL_AUTH_KEY')
    end
  end

  def test_reads_api_url_from_env_file
    with_config do |config|
      write(config.env_path, "DEEPL_API_URL=http://localhost:9999\n")

      assert_equal 'http://localhost:9999', config.setting('DEEPL_API_URL')
    end
  end

  def test_blank_settings_are_nil
    with_config('DEEPL_AUTH_KEY' => '  ') { |config| assert_nil config.setting('DEEPL_AUTH_KEY') }
  end

  def test_not_configured_without_key
    with_config { |config| refute_predicate config, :configured? }
  end

  def test_remembers_languages
    with_config do |config|
      assert_equal %w[PT-BR EN], [config.target, config.source]
      config.remember(target: 'DE', source: 'FR')

      assert_equal %w[DE FR], [config.target, config.source]
      config.remember(target: 'DE', source: '')

      assert_equal ['DE', ''], [config.target, config.source]
    end
  end

  def test_remember_ignores_an_unwritable_state_dir
    with_config do |config|
      write(File.dirname(config.state_path), 'a file where the directory should be')

      assert_nil config.remember(target: 'DE', source: 'FR')
      assert_equal %w[PT-BR EN], [config.target, config.source]
    end
  end

  def test_corrupt_or_unexpected_state_falls_back_to_defaults
    ['[1]', 'not json', '{"target":"XX","source":"EN-XX"}', '"PT-BR"'].each do |content|
      with_config do |config|
        write(config.state_path, content)

        assert_equal %w[PT-BR EN], [config.target, config.source], content
      end
    end
  end

  def test_provider_defaults_to_claude_code_when_nothing_is_configured
    with_config { |config| assert_equal 'claude-code', config.provider }
  end

  def test_provider_defaults_to_claude_code_when_installed
    FakeClaude.open do |fake|
      with_config('DEEPL_AUTH_KEY' => 'd', 'CLAUDE_CODE_BIN' => fake.bin) do |config|
        assert_equal 'claude-code', config.provider
      end
    end
  end

  def test_provider_falls_back_to_first_configured
    with_config('ANTHROPIC_API_KEY' => 'a') { |config| assert_equal 'claude', config.provider }
  end

  def test_provider_prefers_translator_provider_setting
    with_config('DEEPL_AUTH_KEY' => 'd', 'ANTHROPIC_API_KEY' => 'a') do |config|
      write(config.env_path, "TRANSLATOR_PROVIDER=Claude\n")

      assert_equal 'claude', config.provider
    end
  end

  def test_remembered_provider_wins_while_configured
    with_config('DEEPL_AUTH_KEY' => 'd', 'ANTHROPIC_API_KEY' => 'a') do |config|
      config.remember(target: 'DE', source: '', provider: 'claude')

      assert_equal 'claude', config.provider
      config.remember(target: 'FR', source: '')

      assert_equal 'claude', config.provider, 'remembering languages keeps the provider'
    end
  end

  def test_unknown_or_unconfigured_remembered_provider_is_ignored
    %w[nope claude].each do |remembered|
      with_config('DEEPL_AUTH_KEY' => 'd') do |config|
        write(config.state_path, JSON.generate('provider' => remembered))

        assert_equal 'deepl', config.provider, remembered
      end
    end
  end
end

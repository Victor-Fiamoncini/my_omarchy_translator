# frozen_string_literal: true

require_relative 'test_helper'

class ClaudeCodeTest < Minitest::Test
  ClaudeCode = OmarchyTranslator::ClaudeCode
  Error = OmarchyTranslator::Error

  HELLO = { 'detected_source' => 'en', 'text' => 'Olá mundo' }.freeze

  def claude_code(fake, **) = ClaudeCode.new(fake.bin, **)

  def translate_hello(model: nil, stdout: FakeClaude.reply(HELLO))
    FakeClaude.open(stdout: stdout) do |fake|
      [claude_code(fake, model: model).translate('Hello world', target: 'PT-BR'), fake.calls.fetch(0)]
    end
  end

  def flag(argv, name) = argv[argv.index(name) + 1]

  def test_missing_bin_raises_setup_error
    assert_raises(OmarchyTranslator::SetupError) { ClaudeCode.new(nil) }
  end

  def test_translate_reads_structured_output
    result, = translate_hello

    assert_equal({ text: 'Olá mundo', detected_source: 'EN' }, result)
  end

  def test_translate_runs_headless_without_tools_or_session
    argv = translate_hello.last['argv']

    assert_equal %w[-p --output-format json], argv.first(3)
    assert_equal ['', 'low'], [flag(argv, '--tools'), flag(argv, '--effort')]
    assert_empty %w[--no-session-persistence --strict-mcp-config] - argv
  end

  def test_translate_asks_for_the_reply_schema_and_default_model
    argv = translate_hello.last['argv']

    assert_equal %w[detected_source text], JSON.parse(flag(argv, '--json-schema'))['required']
    refute_includes argv, '--model'
  end

  def test_model_is_passed_when_set
    argv = translate_hello(model: 'haiku').last['argv']

    assert_equal 'haiku', flag(argv, '--model')
  end

  def test_prompt_names_the_language_and_text_goes_on_stdin
    call = translate_hello.last

    assert_match(/into Portuguese \(Brazil\)\./, flag(call['argv'], '--system-prompt'))
    assert_equal "<text>\nHello world\n</text>", call['stdin']
  end

  def test_runs_outside_any_project
    assert_equal File.realpath(Dir.tmpdir), File.realpath(translate_hello.last['cwd'])
  end

  def test_falls_back_to_result_text
    stdout = { type: 'result', subtype: 'success', is_error: false, result: '{"detected_source":"fr","text":"Hi"}' }
    result, = translate_hello(stdout: stdout)

    assert_equal({ text: 'Hi', detected_source: 'FR' }, result)
  end

  def test_cli_errors_are_reported
    stdout = { type: 'result', subtype: 'success', is_error: true, result: 'Not logged in · Please run /login' }
    FakeClaude.open(stdout: stdout, status: 1) do |fake|
      error = assert_raises(Error) { claude_code(fake).translate('Hi', target: 'DE') }

      assert_equal 'Claude Code error: Not logged in · Please run /login', error.message
    end
  end

  def test_failure_without_json_uses_stderr
    FakeClaude.open(stdout: '', stderr: "warming up\nboom\n", status: 2) do |fake|
      error = assert_raises(Error) { claude_code(fake).translate('Hi', target: 'DE') }

      assert_equal 'Claude Code failed: boom', error.message
    end
  end

  def test_malformed_output_raises_error
    ['nope', '{"type":"result","subtype":"success","is_error":false}'].each do |stdout|
      FakeClaude.open(stdout: stdout) do |fake|
        error = assert_raises(Error, stdout) { claude_code(fake).translate('Hi', target: 'DE') }

        assert_equal 'Claude Code returned an unexpected response', error.message
      end
    end
  end

  def test_unrunnable_bin_raises_setup_error
    error = assert_raises(OmarchyTranslator::SetupError) do
      ClaudeCode.new('/nonexistent/claude').translate('Hi', target: 'DE')
    end

    assert_equal 'Could not run Claude Code at /nonexistent/claude', error.message
  end

  def test_slow_cli_times_out
    FakeClaude.open(stdout: FakeClaude.reply(HELLO), sleep: 5) do |fake|
      error = assert_raises(Error) { claude_code(fake, timeout: 0.3).translate('Hi', target: 'DE') }

      assert_equal 'Claude Code timed out', error.message
    end
  end

  def config(env) = OmarchyTranslator::Config.new(env: { 'XDG_CONFIG_HOME' => '/nonexistent', **env })

  def test_bin_comes_from_setting_or_path
    FakeClaude.open do |fake|
      assert_equal [fake.bin, fake.bin], [ClaudeCode.bin(config('CLAUDE_CODE_BIN' => fake.bin)),
                                          ClaudeCode.bin(config('PATH' => "/nonexistent:#{fake.dir}"))]
    end
  end

  def test_missing_bin_setting_does_not_fall_back_to_path
    FakeClaude.open do |fake|
      refute ClaudeCode.configured?(config('CLAUDE_CODE_BIN' => '/nonexistent/claude', 'PATH' => fake.dir))
      refute ClaudeCode.configured?(config({}))
    end
  end
end

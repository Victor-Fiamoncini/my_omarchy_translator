# frozen_string_literal: true

require_relative 'test_helper'
require 'open3'
require 'pty'
require 'rbconfig'

class CliTest < Minitest::Test
  BIN = File.expand_path('../bin/omarchy-translate', __dir__)

  # Keep the developer's own keys and real `claude` out of the tests.
  PROVIDER_VARS = %w[TRANSLATOR_PROVIDER DEEPL_AUTH_KEY DEEPL_API_URL ANTHROPIC_API_KEY ANTHROPIC_MODEL
                     ANTHROPIC_API_URL CLAUDE_CODE_MODEL].to_h { |name| [name, nil] }
                                                         .merge('CLAUDE_CODE_BIN' => '/nonexistent/claude').freeze

  def setup
    @home = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@home)
  end

  def cli_env(env)
    { 'XDG_CONFIG_HOME' => "#{@home}/config", 'XDG_STATE_HOME' => "#{@home}/state", **PROVIDER_VARS,
      **CoverageSupport.env, **env }
  end

  def run_cli(*, stdin: '', env: {})
    out, err, status = Open3.capture3(cli_env(env), RbConfig.ruby, BIN, *, stdin_data: stdin)
    [out, err, status.exitstatus]
  end

  # Stand-ins for the desktop tools, first on PATH so the real ones never run. Each logs its argv;
  # wl-paste prints the clipboard given here.
  def desktop_env(clipboard: '')
    bin = "#{@home}/bin"
    FileUtils.mkdir_p(bin)
    %w[wl-paste wl-copy omarchy-notification-send].each do |tool|
      File.write("#{bin}/#{tool}", <<~SH)
        #!/bin/sh
        printf '%s\n' "$*" >> #{@home}/#{tool}.log
        #{"printf '%s' #{clipboard.inspect}" if tool == 'wl-paste'}
      SH
      File.chmod(0o755, "#{bin}/#{tool}")
    end
    { 'PATH' => "#{bin}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}" }
  end

  def desktop_log(tool) = File.exist?("#{@home}/#{tool}.log") ? File.readlines("#{@home}/#{tool}.log", chomp: true) : []

  def json(out) = JSON.parse(out)

  def test_translates_to_json
    FakeDeepL.open do |server|
      out, _, code = run_cli('--json', '--to', 'pt-br', '--', '-Hello-',
                             env: { 'DEEPL_AUTH_KEY' => 'k', 'DEEPL_API_URL' => server.url })

      assert_equal 0, code
      assert_equal({ 'ok' => true, 'text' => 'Olá mundo', 'detectedSource' => 'EN', 'target' => 'PT-BR',
                     'provider' => 'deepl' }, json(out))
      assert_equal ['-Hello-'], server.requests.fetch(0).json['text']
    end
  end

  def test_unwritable_state_keeps_the_translation
    File.write("#{@home}/state", 'not a directory')
    FakeDeepL.open do |server|
      out, _, code = run_cli('--json', 'Hi', env: { 'DEEPL_AUTH_KEY' => 'k', 'DEEPL_API_URL' => server.url })

      assert_equal [0, 'Olá mundo'], [code, json(out)['text']]
    end
  end

  def test_remembers_last_target
    FakeDeepL.open do |server|
      run_cli('--to', 'DE', 'Hi', env: { 'DEEPL_AUTH_KEY' => 'k', 'DEEPL_API_URL' => server.url })
      out, = run_cli('--status')

      assert_equal 'DE', json(out)['target']
    end
  end

  def test_plain_output_reads_stdin
    FakeDeepL.open do |server|
      out, _, code = run_cli(stdin: "Hello\n", env: { 'DEEPL_AUTH_KEY' => 'k', 'DEEPL_API_URL' => server.url })

      assert_equal [0, "Olá mundo\n"], [code, out]
    end
  end

  def test_auto_source_is_not_sent
    FakeDeepL.open do |server|
      run_cli('--json', '--from', 'auto', 'Hi', env: { 'DEEPL_AUTH_KEY' => 'k', 'DEEPL_API_URL' => server.url })

      refute server.requests.fetch(0).json.key?('source_lang')
    end
  end

  def test_missing_setup_is_reported_as_json
    out, _, code = run_cli('--json', 'Hello')

    assert_equal 1, code
    assert_match(/Claude Code not found/, json(out)['error'])
    assert json(out)['needsSetup']
  end

  def test_translates_with_chosen_provider_and_remembers_it
    body = { type: 'message', stop_reason: 'end_turn',
             content: [{ type: 'text', text: '{"detected_source":"en","text":"Hallo"}' }] }
    FakeAPI.open(body: body) do |server|
      env = { 'DEEPL_AUTH_KEY' => 'k', 'ANTHROPIC_API_KEY' => 'a', 'ANTHROPIC_API_URL' => server.url }
      out, _, code = run_cli('--json', '--provider', 'Claude', '--to', 'DE', 'Hello', env: env)

      assert_equal [0, 'Hallo', 'EN', 'claude'], [code, *json(out).values_at('text', 'detectedSource', 'provider')]
      assert_equal 'claude', json(run_cli('--status', env: env).first)['provider']
    end
  end

  def test_unknown_provider_is_reported_as_json
    out, _, code = run_cli('--json', '--provider', 'babelfish', 'Hi', env: { 'DEEPL_AUTH_KEY' => 'k' })

    assert_equal 1, code
    assert_match(/\AUnknown provider babelfish/, json(out)['error'])
  end

  def test_unconfigured_provider_explains_setup
    out, = run_cli('--json', '--provider', 'claude', 'Hi', env: { 'DEEPL_AUTH_KEY' => 'k' })

    assert_equal({ 'ok' => false, 'needsSetup' => true,
                   'error' => "No Anthropic API key. Add ANTHROPIC_API_KEY to #{@home}/config/omarchy/translator.env" },
                 json(out))
  end

  def test_status_lists_providers
    status = json(run_cli('--status', env: { 'ANTHROPIC_API_KEY' => 'a' }).first)

    assert_equal ['claude', true], status.values_at('provider', 'configured')
    assert_equal([%w[deepl DeepL] + [false], %w[claude Claude] + [true], ['claude-code', 'Claude Code', false]],
                 status['providers'].map { |p| p.values_at('id', 'label', 'configured') })
    assert_match(/DEEPL_AUTH_KEY/, status['providers'].first['setupHint'])
  end

  def test_translates_with_claude_code
    FakeClaude.open(stdout: FakeClaude.reply({ detected_source: 'en', text: 'Hallo' })) do |fake|
      out, _, code = run_cli('--json', '--provider', 'claude-code', '--to', 'DE', 'Hello',
                             env: { 'CLAUDE_CODE_BIN' => fake.bin })

      assert_equal [0, 'Hallo', 'EN', 'claude-code'], [code, *json(out).values_at('text', 'detectedSource', 'provider')]
    end
  end

  def test_status_explains_setup_of_the_active_provider
    status = json(run_cli('--status').first)

    assert_equal ['claude-code', false], status.values_at('provider', 'configured')
    assert_match(/CLAUDE_CODE_BIN/, status['setupHint'])
  end

  def test_api_errors_are_reported_as_json
    FakeDeepL.open(status: 403, body: '{}') do |server|
      out, _, code = run_cli('--json', 'Hi', env: { 'DEEPL_AUTH_KEY' => 'bad', 'DEEPL_API_URL' => server.url })

      assert_equal [1, { 'ok' => false, 'error' => 'DeepL rejected the API key' }], [code, json(out)]
    end
  end

  def test_rejects_unsupported_language_and_empty_text
    out, = run_cli('--json', '--to', 'XX', 'Hi', env: { 'DEEPL_AUTH_KEY' => 'k' })

    assert_equal 'Unsupported target language XX', json(out)['error']

    out, = run_cli('--json', '--from', 'XX', 'Hi', env: { 'DEEPL_AUTH_KEY' => 'k' })

    assert_equal 'Unsupported source language XX', json(out)['error']

    out, = run_cli('--json', stdin: " ​\n ", env: { 'DEEPL_AUTH_KEY' => 'k' })

    assert_equal 'Nothing to translate', json(out)['error']
  end

  def test_normalizes_multiline_text_before_sending
    FakeDeepL.open do |server|
      run_cli('--json', stdin: "Hello\r\nwonder-\nful world.\n\n\nBye\n",
                        env: { 'DEEPL_AUTH_KEY' => 'k', 'DEEPL_API_URL' => server.url })

      assert_equal ["Hello wonderful world.\n\nBye"], server.requests.fetch(0).json['text']
    end
  end

  def test_status_survives_corrupt_state
    FileUtils.mkdir_p("#{@home}/state/omarchy")
    File.write("#{@home}/state/omarchy/translator.json", '[1]')
    out, _, code = run_cli('--status')

    assert_equal [0, false, 'PT-BR', 'EN'], [code, json(out)['configured'], json(out)['target'], json(out)['source']]
  end

  def test_languages_lists_targets_and_sources
    out, _, code = run_cli('--languages')

    assert_equal 0, code
    assert_equal 'Portuguese (Brazil)', json(out).dig('targets', 'PT-BR')
    assert_equal ['Portuguese', 'Portuguese (Brazil)'], json(out)['sources'].values_at('PT', 'PT-BR')
  end

  def test_terminal_stdin_is_not_read
    reader, _, pid = PTY.spawn(cli_env('DEEPL_AUTH_KEY' => 'k'), RbConfig.ruby, BIN, '--json')
    out = +''
    begin
      reader.each_line { |line| out << line }
    rescue Errno::EIO # the child closed the terminal
      nil
    end
    _, status = Process.wait2(pid)

    # The terminal carries stderr too (SimpleCov notices under coverage): take the JSON line.
    assert_equal [1, 'Nothing to translate'], [status.exitstatus, json(out[/^\{.*$/])['error']]
  end

  def test_plain_output_reports_errors_on_stderr
    out, err, code = run_cli('Hello')

    assert_equal [1, ''], [code, out]
    assert_match(/\Aomarchy-translate: Claude Code not found/, err)
  end

  def test_translates_the_clipboard
    FakeDeepL.open do |server|
      env = { 'DEEPL_AUTH_KEY' => 'k', 'DEEPL_API_URL' => server.url, **desktop_env(clipboard: 'Hello') }
      out, _, code = run_cli('--json', '--clipboard', env: env)

      assert_equal [0, 'Olá mundo'], [code, json(out)['text']]
      assert_equal ['Hello'], server.requests.fetch(0).json['text']
      assert_equal ['--no-newline'], desktop_log('wl-paste')
    end
  end

  def test_empty_clipboard_is_reported
    out, _, code = run_cli('--json', '--clipboard', env: { 'DEEPL_AUTH_KEY' => 'k', **desktop_env(clipboard: ' ') })

    assert_equal [1, 'Clipboard is empty'], [code, json(out)['error']]
  end

  def test_notify_copies_and_shows_the_translation
    FakeDeepL.open do |server|
      run_cli('--notify', 'Hi', env: { 'DEEPL_AUTH_KEY' => 'k', 'DEEPL_API_URL' => server.url, **desktop_env })

      assert_equal ['Olá mundo'], desktop_log('wl-copy')
      assert_equal ['-g 󰗊 -u low EN → PT-BR · DeepL (copied) Olá mundo'], desktop_log('omarchy-notification-send')
    end
  end

  def test_notify_shows_failures
    run_cli('--notify', 'Hi', env: desktop_env)

    assert_equal [], desktop_log('wl-copy')
    assert_match(/\A-g 󰗊 -u normal Translation failed Claude Code not found/,
                 desktop_log('omarchy-notification-send').first)
  end

  def test_unexpected_errors_are_still_reported_as_json
    env = { 'DEEPL_AUTH_KEY' => 'k', 'DEEPL_API_URL' => 'http://[' } # URI() raises, not an Error
    out, _, code = run_cli('--json', 'Hi', env: env)

    assert_equal 1, code
    assert_match(/\AUnexpected error: URI::InvalidURIError: /, json(out)['error'])

    run_cli('--notify', 'Hi', env: env.merge(desktop_env))

    assert_equal ['-g 󰗊 -u normal Translation failed Unexpected error, see terminal output'],
                 desktop_log('omarchy-notification-send')
  end

  def test_invalid_option_exits_with_usage
    _, err, code = run_cli('--nope')

    assert_equal 2, code
    assert_match(/invalid option: --nope/, err)
  end
end

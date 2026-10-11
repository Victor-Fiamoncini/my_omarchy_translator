# frozen_string_literal: true

require_relative 'test_helper'

class ClaudeTest < Minitest::Test
  Claude = OmarchyTranslator::Claude
  Error = OmarchyTranslator::Error

  def reply(text, stop_reason: 'end_turn')
    { type: 'message', role: 'assistant', stop_reason: stop_reason, content: [{ type: 'text', text: text }] }
  end

  def claude(server, model: nil) = Claude.new('secret', model: model, base_url: server.url)

  def test_missing_key_raises
    assert_raises(OmarchyTranslator::SetupError) { Claude.new(' ') }
  end

  def translate_hello(model: nil)
    FakeAPI.open(body: reply('{"detected_source":"en","text":"Olá mundo"}')) do |server|
      [claude(server, model: model).translate('Hello world', target: 'PT-BR'), server.requests.fetch(0)]
    end
  end

  def test_translate_parses_structured_reply
    result, request = translate_hello

    assert_equal({ text: 'Olá mundo', detected_source: 'EN' }, result)
    assert_equal '/v1/messages', request.path
  end

  def test_translate_names_a_regional_source_in_the_prompt
    FakeAPI.open(body: reply('{"detected_source":"pt","text":"Hello"}')) do |server|
      result = claude(server).translate('Olá', target: 'EN-US', source: 'PT-BR')

      assert_includes server.requests.fetch(0).json['system'], 'The source language is Portuguese (Brazil).'
      assert_equal({ text: 'Hello', detected_source: 'PT' }, result)
    end
  end

  def test_translate_sends_auth_version_and_fallback_headers
    _, request = translate_hello

    assert_equal %w[secret 2023-06-01 server-side-fallback-2026-07-01],
                 request.headers.values_at('x-api-key', 'anthropic-version', 'anthropic-beta')
  end

  def test_translate_asks_for_low_effort_json_with_fallbacks
    body = translate_hello.last.json

    assert_equal ['claude-opus-5-5', 'default'], body.values_at('model', 'fallbacks')
    assert_equal %w[low json_schema], [body.dig('output_config', 'effort'), body.dig('output_config', 'format', 'type')]
  end

  def test_translate_prompt_names_the_language_and_wraps_the_text
    body = translate_hello.last.json

    assert_match(/into Portuguese \(Brazil\)\./, body['system'])
    assert_equal [{ 'role' => 'user', 'content' => "<text>\nHello world\n</text>" }], body['messages']
  end

  def test_haiku_gets_no_effort_or_fallbacks
    _, request = translate_hello(model: 'claude-haiku-4-5')

    refute request.headers.key?('anthropic-beta')
    refute request.json.key?('fallbacks')
    refute request.json['output_config'].key?('effort')
  end

  def test_haiku_5_gets_low_effort_without_fallbacks
    _, request = translate_hello(model: 'claude-haiku-5-5')

    assert_equal 'low', request.json.dig('output_config', 'effort')
    refute request.json.key?('fallbacks')
  end

  def translate_reply(text)
    FakeAPI.open(body: reply(text)) { |server| claude(server).translate('Hello', target: 'PT-BR') }
  end

  def test_plain_text_reply_is_kept
    assert_equal({ text: 'Olá', detected_source: nil }, translate_reply("Olá\n"))
  end

  def test_json_reply_that_is_not_an_object_is_kept_as_text
    assert_equal({ text: '["Olá"]', detected_source: nil }, translate_reply('["Olá"]'))
  end

  def test_json_reply_inside_prose_is_parsed
    assert_equal({ text: 'Olá', detected_source: 'EN' },
                 translate_reply("Here it is:\n```json\n{\"detected_source\":\"en\",\"text\":\"Olá\"}\n```"))
  end

  def test_json_reply_without_a_translation_is_an_error
    ['{"detected_source":"en","text":""}', '{"detected_source":"en"}', 'Sure: {"text": 1}'].each do |text|
      error = assert_raises(Error, text) { translate_reply(text) }

      assert_equal 'Claude returned an unexpected response', error.message
    end
  end

  def test_skips_non_text_blocks
    body = reply('{"detected_source":"fr","text":"Hello"}')
    body[:content].unshift({ type: 'fallback', from: { model: 'a' }, to: { model: 'b' } })

    FakeAPI.open(body: body) do |server|
      assert_equal({ text: 'Hello', detected_source: 'FR' }, claude(server).translate('Bonjour', target: 'EN-US'))
    end
  end

  def test_stop_reasons_become_errors
    { 'refusal' => 'Claude declined to translate this text',
      'max_tokens' => 'Claude stopped early, the text may be too long' }.each do |reason, message|
      FakeAPI.open(body: reply('', stop_reason: reason)) do |server|
        error = assert_raises(Error) { claude(server).translate('Hi', target: 'DE') }

        assert_equal message, error.message
      end
    end
  end

  def test_http_errors_become_friendly_messages
    {
      401 => 'Claude rejected the API key',
      429 => 'Too many requests, try again shortly',
      529 => 'Claude is overloaded, try again shortly'
    }.each do |status, message|
      FakeAPI.open(status: status, body: { type: 'error', error: { type: 'x', message: 'y' } }) do |server|
        error = assert_raises(Error) { claude(server).translate('Hi', target: 'DE') }

        assert_equal message, error.message
      end
    end
  end

  def test_unknown_http_error_includes_api_message
    body = { type: 'error', error: { type: 'invalid_request_error', message: 'model: not found' } }
    FakeAPI.open(status: 404, body: body) do |server|
      error = assert_raises(Error) { claude(server).translate('Hi', target: 'DE') }

      assert_equal 'Claude error 404: model: not found', error.message
    end
  end

  def test_malformed_success_body_raises_error
    ['{}', '{"content":[]}', 'nope'].each do |body|
      FakeAPI.open(body: body) do |server|
        error = assert_raises(Error, body) { claude(server).translate('Hi', target: 'DE') }

        assert_equal 'Claude returned an unexpected response', error.message
      end
    end
  end
end

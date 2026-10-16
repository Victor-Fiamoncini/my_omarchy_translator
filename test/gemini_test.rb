# frozen_string_literal: true

require_relative 'test_helper'

class GeminiTest < Minitest::Test
  Gemini = OmarchyTranslator::Gemini
  Error = OmarchyTranslator::Error

  def reply(text, finish_reason: 'STOP')
    { candidates: [{ content: { role: 'model', parts: [{ text: text }] }, finishReason: finish_reason }] }
  end

  def gemini(server, model: nil) = Gemini.new('secret', model: model, base_url: server.url)

  def test_missing_key_raises
    assert_raises(OmarchyTranslator::SetupError) { Gemini.new(' ') }
  end

  def translate_hello(model: nil)
    FakeAPI.open(body: reply('{"detected_source":"en","text":"Olá mundo"}')) do |server|
      [gemini(server, model: model).translate('Hello world', target: 'PT-BR'), server.requests.fetch(0)]
    end
  end

  def test_translate_parses_structured_reply
    result, request = translate_hello

    assert_equal({ text: 'Olá mundo', detected_source: 'EN' }, result)
    assert_equal '/v1beta/models/gemini-3.5-flash-lite:generateContent', request.path
    assert_equal 'secret', request.headers['x-goog-api-key']
  end

  def test_model_can_be_chosen
    _, request = translate_hello(model: 'gemini-3.8-flash')

    assert_equal '/v1beta/models/gemini-3.8-flash:generateContent', request.path
  end

  def test_translate_prompt_names_the_language_and_wraps_the_text
    body = translate_hello.last.json

    assert_match(/into Portuguese \(Brazil\)\./, body.dig('systemInstruction', 'parts', 0, 'text'))
    assert_equal [{ 'role' => 'user', 'parts' => [{ 'text' => "<text>\nHello world\n</text>" }] }], body['contents']
  end

  def test_translate_asks_for_json
    config = translate_hello.last.json['generationConfig']

    assert_equal 'application/json', config['responseMimeType']
    assert_equal %w[detected_source text], config.dig('responseJsonSchema', 'required')
  end

  def test_translate_names_a_regional_source_in_the_prompt
    FakeAPI.open(body: reply('{"detected_source":"pt","text":"Hello"}')) do |server|
      result = gemini(server).translate('Olá', target: 'EN-US', source: 'PT-BR')

      assert_includes server.requests.fetch(0).json.dig('systemInstruction', 'parts', 0, 'text'),
                      'The source language is Portuguese (Brazil).'
      assert_equal({ text: 'Hello', detected_source: 'PT' }, result)
    end
  end

  def test_joins_split_text_parts
    body = reply('{"detected_source":"fr",')
    body[:candidates][0][:content][:parts] += [{ thought: true }, { text: '"text":"Hello"}' }]

    FakeAPI.open(body: body) do |server|
      assert_equal({ text: 'Hello', detected_source: 'FR' }, gemini(server).translate('Bonjour', target: 'EN-US'))
    end
  end

  def test_plain_text_reply_is_kept
    FakeAPI.open(body: reply("Olá\n")) do |server|
      assert_equal({ text: 'Olá', detected_source: nil }, gemini(server).translate('Hello', target: 'PT-BR'))
    end
  end

  def assert_translate_error(message, status: 200, body: {})
    FakeAPI.open(status: status, body: body) do |server|
      error = assert_raises(Error) { gemini(server).translate('Hi', target: 'DE') }

      assert_equal message, error.message
    end
  end

  def test_blocked_prompt_is_declined
    assert_translate_error 'Gemini declined to translate this text', body: { promptFeedback: { blockReason: 'SAFETY' } }
  end

  def test_finish_reasons_become_errors
    { 'SAFETY' => 'Gemini declined to translate this text',
      'RECITATION' => 'Gemini declined to translate this text',
      'MAX_TOKENS' => 'Gemini stopped early, the text may be too long' }.each do |reason, message|
      assert_translate_error message, body: reply('', finish_reason: reason)
    end
  end

  def test_rejected_key_becomes_a_friendly_message
    bad_key = { error: { code: 400, message: 'API key not valid.', status: 'INVALID_ARGUMENT',
                         details: [{ reason: 'API_KEY_INVALID' }] } }

    assert_translate_error 'Gemini rejected the API key', status: 400, body: bad_key
  end

  def test_http_errors_become_friendly_messages
    {
      403 => 'Gemini rejected the API key',
      429 => 'Gemini quota reached (the free tier has daily limits), try again later',
      503 => 'Gemini is overloaded, try again shortly'
    }.each do |status, message|
      assert_translate_error message, status: status, body: { error: { message: 'x' } }
    end
  end

  def test_unknown_http_error_includes_api_message
    assert_translate_error 'Gemini error 400: models/nope is not found',
                           status: 400, body: { error: { message: 'models/nope is not found' } }
  end

  def test_malformed_success_body_raises_error
    ['{}', '{"candidates":[]}', '{"candidates":[{"content":{}}]}', 'nope'].each do |body|
      assert_translate_error 'Gemini returned an unexpected response', body: body
    end
  end
end

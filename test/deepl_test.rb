# frozen_string_literal: true

require_relative 'test_helper'

class DeepLTest < Minitest::Test
  DeepL = OmarchyTranslator::DeepL
  Error = OmarchyTranslator::Error

  def test_free_keys_use_free_endpoint
    assert_equal 'https://api-free.deepl.com', DeepL.new('abc:fx').base_uri.to_s
  end

  def test_pro_keys_use_pro_endpoint
    assert_equal 'https://api.deepl.com', DeepL.new('abc').base_uri.to_s
  end

  def test_missing_key_raises
    assert_raises(Error) { DeepL.new('  ') }
  end

  def test_translate_returns_text_and_detected_source
    FakeDeepL.open do |server|
      result = DeepL.new('secret:fx', base_url: server.url).translate('Hello world', target: 'PT-BR')

      assert_equal({ text: 'Olá mundo', detected_source: 'EN' }, result)
    end
  end

  def test_translate_sends_authenticated_json_request
    FakeDeepL.open do |server|
      DeepL.new('secret:fx', base_url: server.url).translate('Hello world', target: 'PT-BR')
      request = server.requests.fetch(0)

      assert_equal ['POST', '/v2/translate'], [request.verb, request.path]
      assert_equal 'DeepL-Auth-Key secret:fx', request.headers['authorization']
      assert_equal({ 'text' => ['Hello world'], 'target_lang' => 'PT-BR' }, request.json)
    end
  end

  def test_translate_sends_source_language_when_given
    FakeDeepL.open do |server|
      DeepL.new('k', base_url: server.url).translate('Hi', target: 'DE', source: 'EN')

      assert_equal 'EN', server.requests.fetch(0).json['source_lang']
    end
  end

  def test_translate_sends_a_regional_source_as_its_base_language
    FakeDeepL.open do |server|
      DeepL.new('k', base_url: server.url).translate('Olá', target: 'DE', source: 'PT-BR')

      assert_equal 'PT', server.requests.fetch(0).json['source_lang']
    end
  end

  def test_http_errors_become_friendly_messages
    {
      403 => 'DeepL rejected the API key',
      429 => 'Too many requests, try again shortly',
      456 => 'DeepL character quota exceeded'
    }.each do |status, message|
      FakeDeepL.open(status: status, body: '{}') do |server|
        error = assert_raises(Error) { DeepL.new('k', base_url: server.url).translate('Hi', target: 'DE') }

        assert_equal message, error.message
      end
    end
  end

  def test_unknown_http_error_includes_deepl_message
    FakeDeepL.open(status: 400, body: '{"message":"Value for target_lang not supported"}') do |server|
      error = assert_raises(Error) { DeepL.new('k', base_url: server.url).translate('Hi', target: 'DE') }

      assert_equal 'DeepL error 400: Value for target_lang not supported', error.message
    end
  end

  def test_malformed_success_body_raises_error
    ['not json', '{}', '{"translations":[]}', '[1]'].each do |body|
      FakeDeepL.open(body: body) do |server|
        assert_raises(Error, body) { DeepL.new('k', base_url: server.url).translate('Hi', target: 'DE') }
      end
    end
  end

  def test_unreachable_server_raises_error
    port = TCPServer.open('127.0.0.1', 0) { |s| s.addr[1] } # bound then released: nothing listens
    error = assert_raises(Error) { DeepL.new('k', base_url: "http://127.0.0.1:#{port}").translate('Hi', target: 'DE') }

    assert_match(/\ACould not reach DeepL/, error.message)
  end
end

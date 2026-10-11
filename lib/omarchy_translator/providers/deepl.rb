# frozen_string_literal: true

module OmarchyTranslator
  # DeepL v2 REST API client.
  class DeepL < Provider
    ID = 'deepl'
    LABEL = 'DeepL'
    FREE_HOST = 'api-free.deepl.com'
    PRO_HOST = 'api.deepl.com'

    def self.configured?(config) = !config.setting('DEEPL_AUTH_KEY').nil?

    def self.setup_hint(config) = "No DeepL API key. Add DEEPL_AUTH_KEY to #{config.env_path}"

    def self.from_config(config)
      new(config.setting('DEEPL_AUTH_KEY'), base_url: config.setting('DEEPL_API_URL'))
    end

    def initialize(auth_key, base_url: nil)
      super()
      raise SetupError, 'DeepL API key is missing' if auth_key.to_s.strip.empty?

      @auth_key = auth_key.strip
      @base_url = base_url.to_s.strip.empty? ? nil : URI(base_url)
    end

    # Free-plan keys end in ":fx" and must use the free endpoint.
    def host
      @auth_key.end_with?(':fx') ? FREE_HOST : PRO_HOST
    end

    def base_uri
      @base_url || URI::HTTPS.build(host: host)
    end

    def translate(text, target:, source: nil)
      response = post_json(endpoint(base_uri, '/v2/translate'), request_body(text, target, source),
                           'Authorization' => "DeepL-Auth-Key #{@auth_key}")
      translation = response.fetch('translations').first
      raise Error, 'DeepL returned no translation' unless translation.is_a?(Hash) && translation['text']

      { text: translation['text'], detected_source: translation['detected_source_language'] }
    rescue KeyError, NoMethodError, TypeError
      raise unexpected_response
    end

    private

    # DeepL's source_lang takes no regional variant: PT-BR is sent as PT.
    def request_body(text, target, source)
      body = { text: [text], target_lang: target }
      body[:source_lang] = source.split('-').first if source && !source.empty?
      body
    end

    def status_messages
      super.merge(403 => 'DeepL rejected the API key', 456 => 'DeepL character quota exceeded')
    end
  end
end

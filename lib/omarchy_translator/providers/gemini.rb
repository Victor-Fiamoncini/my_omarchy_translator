# frozen_string_literal: true

module OmarchyTranslator
  # Google Gemini through the Gemini API (generateContent). A free key from aistudio.google.com works.
  class Gemini < Provider
    include LLMTranslation

    ID = 'gemini'
    LABEL = 'Gemini'
    TIMEOUT = LLMTranslation::TIMEOUT
    DEFAULT_URL = 'https://generativelanguage.googleapis.com'
    # Flash-Lite: free tier, fast, and a higher free daily quota than Flash.
    DEFAULT_MODEL = 'gemini-3.5-flash-lite'

    DECLINED = %w[SAFETY RECITATION BLOCKLIST PROHIBITED_CONTENT SPII LANGUAGE].freeze

    def self.configured?(config) = !config.setting('GEMINI_API_KEY').nil?

    def self.setup_hint(config)
      "No Gemini API key. Get a free one at aistudio.google.com and add GEMINI_API_KEY to #{config.env_path}"
    end

    def self.from_config(config)
      new(config.setting('GEMINI_API_KEY'), model: config.setting('GEMINI_MODEL'),
                                            base_url: config.setting('GEMINI_API_URL'))
    end

    def initialize(api_key, model: nil, base_url: nil)
      super()
      raise SetupError, 'Gemini API key is missing' if api_key.to_s.strip.empty?

      @api_key = api_key.strip
      @model = model || DEFAULT_MODEL
      @base_url = base_url || DEFAULT_URL
    end

    def translate(text, target:, source: nil)
      response = post_json(endpoint(@base_url, "/v1beta/models/#{@model}:generateContent"),
                           request_body(text, target, source), 'x-goog-api-key' => @api_key)
      raise declined if response.dig('promptFeedback', 'blockReason')

      candidate = response.fetch('candidates').first
      check_finish_reason(candidate['finishReason'])
      parse_reply(candidate_text(candidate), source)
    rescue KeyError, NoMethodError, TypeError
      raise unexpected_response
    end

    private

    def request_body(text, target, source)
      { systemInstruction: { parts: [{ text: system_prompt(target, source) }] },
        contents: [{ role: 'user', parts: [{ text: user_message(text) }] }],
        generationConfig: { responseMimeType: 'application/json', responseJsonSchema: REPLY_SCHEMA } }
    end

    # Thinking models can add parts without text; the reply may also be split across parts.
    def candidate_text(candidate)
      candidate.dig('content', 'parts')&.filter_map { |part| part['text'] }&.join
    end

    def check_finish_reason(reason)
      raise declined if DECLINED.include?(reason)
      raise Error, 'Gemini stopped early, the text may be too long' if reason == 'MAX_TOKENS'
    end

    def declined = Error.new('Gemini declined to translate this text')

    # A bad key is a 400 with reason API_KEY_INVALID, not a 401.
    def handle(response)
      bad_key = response.code.to_i == 400 && response.body.to_s.include?('API_KEY_INVALID')
      raise Error, 'Gemini rejected the API key' if bad_key

      super
    end

    def status_messages
      super.merge(429 => 'Gemini quota reached (the free tier has daily limits), try again later',
                  503 => 'Gemini is overloaded, try again shortly')
    end
  end
end

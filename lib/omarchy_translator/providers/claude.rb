# frozen_string_literal: true

module OmarchyTranslator
  # Claude through the Anthropic Messages API.
  class Claude < Provider
    include LLMTranslation

    ID = 'claude'
    LABEL = 'Claude'
    TIMEOUT = LLMTranslation::TIMEOUT
    DEFAULT_URL = 'https://api.anthropic.com'
    DEFAULT_MODEL = 'claude-opus-5-5'
    API_VERSION = '2023-06-01'

    EFFORT_MODELS = /\Aclaude-(?:opus|sonnet|fable|haiku)-5/
    FALLBACK_MODELS = %w[claude-opus-5-5 claude-opus-5 claude-sonnet-5-5 claude-fable-5-1].freeze
    FALLBACK_BETA = 'server-side-fallback-2026-07-01'

    def self.configured?(config) = !config.setting('ANTHROPIC_API_KEY').nil?

    def self.setup_hint(config) = "No Anthropic API key. Add ANTHROPIC_API_KEY to #{config.env_path}"

    def self.from_config(config)
      new(config.setting('ANTHROPIC_API_KEY'), model: config.setting('ANTHROPIC_MODEL'),
                                               base_url: config.setting('ANTHROPIC_API_URL'))
    end

    def initialize(api_key, model: nil, base_url: nil)
      super()
      raise SetupError, 'Anthropic API key is missing' if api_key.to_s.strip.empty?

      @api_key = api_key.strip
      @model = model || DEFAULT_MODEL
      @base_url = base_url || DEFAULT_URL
    end

    def translate(text, target:, source: nil)
      response = post_json(endpoint(@base_url, '/v1/messages'), request_body(text, target, source), headers)
      check_stop_reason(response['stop_reason'])

      block = response.fetch('content').find { |b| b['type'] == 'text' }
      parse_reply(block&.fetch('text'), source)
    rescue KeyError, NoMethodError, TypeError
      raise unexpected_response
    end

    private

    def request_body(text, target, source)
      output_config = { format: { type: 'json_schema', schema: REPLY_SCHEMA } }
      output_config[:effort] = 'low' if @model.match?(EFFORT_MODELS)
      body = { model: @model, max_tokens: 16_000, system: system_prompt(target, source),
               messages: [{ role: 'user', content: user_message(text) }], output_config: output_config }
      body[:fallbacks] = 'default' if fallbacks?
      body
    end

    def headers
      headers = { 'x-api-key' => @api_key, 'anthropic-version' => API_VERSION }
      headers['anthropic-beta'] = FALLBACK_BETA if fallbacks?
      headers
    end

    def fallbacks? = FALLBACK_MODELS.include?(@model)

    def check_stop_reason(reason)
      case reason
      when 'refusal' then raise Error, 'Claude declined to translate this text'
      when 'max_tokens' then raise Error, 'Claude stopped early, the text may be too long'
      end
    end

    def status_messages
      super.merge(529 => 'Claude is overloaded, try again shortly')
    end
  end
end

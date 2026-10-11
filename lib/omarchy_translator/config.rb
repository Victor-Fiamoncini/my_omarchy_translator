# frozen_string_literal: true

module OmarchyTranslator
  # Settings from ~/.config/omarchy/translator.env, overridden by the process environment.
  class Config
    attr_reader :env_path, :state_path

    def initialize(env: ENV)
      @env = env
      config_home = env.fetch('XDG_CONFIG_HOME', File.join(Dir.home, '.config'))
      state_home = env.fetch('XDG_STATE_HOME', File.join(Dir.home, '.local', 'state'))
      @env_path = File.join(config_home, 'omarchy', 'translator.env')
      @state_path = File.join(state_home, 'omarchy', 'translator.json')
    end

    def setting(name)
      value = @env[name]
      value = read_env_file[name] if value.to_s.strip.empty?
      value.to_s.strip.empty? ? nil : value.strip
    end

    def configured?(provider_id = provider)
      PROVIDERS.fetch(provider_id).configured?(self)
    end

    def provider
      remembered = state['provider']
      return remembered if PROVIDERS.key?(remembered) && configured?(remembered)

      default = setting('TRANSLATOR_PROVIDER').to_s.downcase
      default = DEFAULT_PROVIDER unless PROVIDERS.key?(default)
      return default if configured?(default)

      PROVIDERS.keys.find { |id| configured?(id) } || default
    end

    # A hand-edited or half-written file must never break translation.
    def state
      data = JSON.parse(File.read(state_path))
      data.is_a?(Hash) ? data : {}
    rescue SystemCallError, JSON::ParserError
      {}
    end

    def target
      value = state['target']
      TARGET_LANGUAGES.key?(value) ? value : DEFAULT_TARGET
    end

    # '' is a remembered auto-detect choice, so only a missing or unknown value falls back to the default.
    def source
      value = state['source']
      value == '' || SOURCE_LANGUAGES.key?(value) ? value : DEFAULT_SOURCE
    end

    # Best effort: an unwritable state dir (read-only, full disk) must never cost a finished translation.
    def remember(target:, source:, provider: nil)
      data = { 'target' => target, 'source' => source.to_s }
      data['provider'] = provider || state['provider']
      FileUtils.mkdir_p(File.dirname(state_path))
      File.write(state_path, JSON.generate(data.compact))
    rescue SystemCallError
      nil
    end

    private

    def read_env_file
      @read_env_file ||= File.readlines(env_path, chomp: true).each_with_object({}) do |line, vars|
        next if line.strip.empty? || line.lstrip.start_with?('#')

        name, value = line.sub(/\A\s*export\s+/, '').split('=', 2)
        vars[name.strip] = unquote(value.strip) if value
      end
    rescue SystemCallError
      {}
    end

    def unquote(value)
      value.match(/\A(["'])(.*)\1\z/m) ? Regexp.last_match(2) : value
    end
  end
end

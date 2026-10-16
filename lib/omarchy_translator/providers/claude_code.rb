# frozen_string_literal: true

module OmarchyTranslator
  # Claude through the local Claude Code CLI (`claude -p`), using the user's login.
  class ClaudeCode < Provider
    include LLMTranslation

    ID = 'claude-code'
    LABEL = 'Claude Code'
    # Must stay under the popup's 65s watchdog.
    TIMEOUT = 60

    def self.bin(config)
      explicit = config.setting('CLAUDE_CODE_BIN')
      return (File.executable?(explicit) ? explicit : nil) if explicit

      config.setting('PATH').to_s.split(File::PATH_SEPARATOR).each do |dir|
        path = File.join(dir, 'claude')
        return path if File.file?(path) && File.executable?(path)
      end
      nil
    end

    def self.configured?(config) = !bin(config).nil?

    def self.setup_hint(config)
      'Claude Code not found. Install it and run `claude` once to log in, ' \
        "or set CLAUDE_CODE_BIN in #{config.env_path}"
    end

    def self.from_config(config)
      new(bin(config), model: config.setting('CLAUDE_CODE_MODEL'))
    end

    def initialize(bin, model: nil, timeout: TIMEOUT)
      super()
      raise SetupError, 'Claude Code was not found' if bin.to_s.strip.empty?

      @bin = bin
      @model = model
      @timeout = timeout
    end

    def translate(text, target:, source: nil)
      data = parse_output(*run(command(target, source), user_message(text)))
      reply = data['structured_output']
      parse_reply(reply.is_a?(Hash) ? JSON.generate(reply) : data['result'], source)
    end

    private

    attr_reader :timeout

    def command(target, source)
      argv = [@bin, '-p', '--output-format', 'json',
              '--json-schema', JSON.generate(REPLY_SCHEMA),
              '--system-prompt', system_prompt(target, source),
              '--tools', '', '--no-session-persistence', '--effort', 'low', '--strict-mcp-config']
      argv.push('--model', @model) if @model
      argv
    end

    # Runs from a neutral directory so no project CLAUDE.md is picked up.
    def run(argv, input)
      Open3.popen3(*argv, chdir: Dir.tmpdir) do |stdin, stdout, stderr, wait_thr|
        readers = [stdout, stderr].map { |io| Thread.new { read_all(io) } }
        write_input(stdin, input)
        wait_for(wait_thr)
        [*readers.map(&:value), wait_thr.value]
      end
    rescue Errno::ENOENT, Errno::EACCES
      raise SetupError, "Could not run #{label} at #{@bin}"
    end

    def wait_for(wait_thr)
      return if wait_thr.join(timeout)

      kill(wait_thr.pid)
      raise Error, "#{label} timed out"
    end

    def read_all(io)
      io.read
    rescue IOError
      ''
    end

    def write_input(stdin, input)
      stdin.write(input)
    rescue Errno::EPIPE
      nil
    ensure
      stdin.close
    end

    def kill(pid)
      Process.kill('TERM', pid)
    rescue SystemCallError
      nil
    end

    def parse_output(out, err, status)
      data = cli_result(out)
      raise failure(err, status) unless data
      raise Error, "#{label} error: #{data['result'] || data['subtype']}" if cli_error?(data)

      data
    end

    def cli_result(out)
      data = JSON.parse(out)
      data if data.is_a?(Hash)
    rescue JSON::ParserError, TypeError
      nil
    end

    def cli_error?(data) = data['is_error'] || data['subtype'] != 'success'

    def failure(err, status)
      return unexpected_response if status.success?

      detail = err.to_s.lines.map(&:strip).reject(&:empty?).last
      Error.new("#{label} failed#{": #{detail}" if detail}")
    end
  end
end

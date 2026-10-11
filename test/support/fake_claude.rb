# frozen_string_literal: true

require 'json'
require 'rbconfig'
require 'tmpdir'

# A stand-in `claude` executable that logs each call and prints a canned reply.
class FakeClaude
  attr_reader :bin, :dir

  def initialize(stdout: nil, stderr: '', status: 0, sleep: 0)
    @dir = Dir.mktmpdir('fake-claude')
    @bin = File.join(@dir, 'claude')
    @log = File.join(@dir, 'calls.jsonl')
    stdout = JSON.generate(stdout) if stdout.is_a?(Hash)
    File.write(@bin, script(stdout.to_s, stderr, status, sleep))
    File.chmod(0o755, @bin)
  end

  def self.open(**)
    fake = new(**)
    yield fake
  ensure
    fake&.close
  end

  def self.reply(structured, result: nil)
    { type: 'result', subtype: 'success', is_error: false,
      result: result || JSON.generate(structured), structured_output: structured }.compact
  end

  def calls
    File.exist?(@log) ? File.readlines(@log).map { |line| JSON.parse(line) } : []
  end

  def close
    FileUtils.remove_entry(@dir)
  end

  private

  def script(stdout, stderr, status, sleep)
    <<~RUBY
      #!#{RbConfig.ruby}
      require 'json'
      input = $stdin.read
      File.open(#{@log.inspect}, 'a') { |f| f.puts JSON.generate(argv: ARGV, stdin: input, cwd: Dir.pwd) }
      sleep #{sleep}
      $stderr.write #{stderr.inspect}
      $stdout.write #{stdout.inspect}
      exit #{status}
    RUBY
  end
end

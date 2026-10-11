# frozen_string_literal: true

require 'json'
require 'socket'

# A tiny HTTP server standing in for a provider API.
class FakeAPI
  Request = Struct.new(:verb, :path, :headers, :body, keyword_init: true) do
    def json = JSON.parse(body)
  end

  attr_reader :url, :requests

  def initialize(status: 200, body: '{}')
    @status = status
    @body = (body.is_a?(String) ? body : JSON.generate(body)).b
    @requests = []
    @server = TCPServer.new('127.0.0.1', 0)
    @url = "http://127.0.0.1:#{@server.addr[1]}"
    @thread = Thread.new { serve }
  end

  def self.open(**)
    server = new(**)
    yield server
  ensure
    server&.close
  end

  def close
    @server.close
    @thread.join(1)
  end

  private

  def serve
    loop { handle(@server.accept) }
  rescue IOError, SystemCallError
    nil
  end

  def handle(client)
    verb, path = client.gets.to_s.split
    headers = read_headers(client)
    body = client.read(headers.fetch('content-length', '0').to_i)
    @requests << Request.new(verb: verb, path: path, headers: headers, body: body)
    client.write("HTTP/1.1 #{@status} Fake\r\nContent-Type: application/json\r\n" \
                 "Content-Length: #{@body.bytesize}\r\nConnection: close\r\n\r\n")
    client.write(@body)
  ensure
    client.close
  end

  def read_headers(client)
    headers = {}
    while (line = client.gets) && line != "\r\n"
      name, value = line.split(':', 2)
      headers[name.downcase] = value.strip
    end
    headers
  end
end

# FakeAPI answering like DeepL by default.
class FakeDeepL < FakeAPI
  SUCCESS = { translations: [{ detected_source_language: 'EN', text: 'Olá mundo' }] }.freeze

  def initialize(status: 200, body: SUCCESS)
    super
  end
end

# frozen_string_literal: true

module OmarchyTranslator
  # Base class for provider clients: JSON POST over Net::HTTP with user-facing errors.
  class Provider
    TIMEOUT = 10

    def self.label = self::LABEL

    def label = self.class.label

    def self.canonical_source(code)
      base = code.to_s.split(/[-_]/).first.to_s.upcase
      { 'IW' => 'HE', 'NO' => 'NB' }.fetch(base, base).then { |c| c.empty? ? nil : c }
    end

    private

    def timeout = self.class::TIMEOUT

    def unexpected_response
      Error.new("#{label} returned an unexpected response")
    end

    def result(text, detected, source)
      raise unexpected_response unless text.is_a?(String)

      { text: text, detected_source: self.class.canonical_source(detected || source) }
    end

    def post_json(url, body, headers = {})
      uri = URI(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                                     open_timeout: timeout, read_timeout: timeout) do |http|
        http.request(build_request(uri, body, headers))
      end
      handle(response)
    rescue *NETWORK_ERRORS => e
      raise Error, "Could not reach #{label} (#{e.class.name.split('::').last})"
    end

    def build_request(uri, body, headers)
      Net::HTTP::Post.new(uri).tap do |request|
        headers.each { |name, value| request[name] = value }
        request['Content-Type'] = 'application/json'
        request.body = JSON.generate(body)
      end
    end

    def handle(response)
      status = response.code.to_i
      return parse_json(response.body) if status == 200

      known = status_messages[status]
      raise Error, known if known

      message = error_detail(response.body)
      raise Error, "#{label} error #{status}#{": #{message}" if message}"
    end

    def status_messages
      { 401 => "#{label} rejected the API key", 403 => "#{label} rejected the API key",
        429 => 'Too many requests, try again shortly' }
    end

    def error_detail(body)
      data = JSON.parse(body)
      return unless data.is_a?(Hash)

      error = data['error']
      message = data['message'] || (error.is_a?(Hash) ? error['message'] : error)
      message.is_a?(String) && !message.empty? ? message : nil
    rescue JSON::ParserError, TypeError
      nil
    end

    def parse_json(body)
      JSON.parse(body)
    rescue JSON::ParserError, TypeError
      raise unexpected_response
    end

    def endpoint(base, path)
      "#{base.to_s.chomp('/')}#{path}"
    end
  end
end

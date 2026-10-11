# frozen_string_literal: true

require 'json'
require 'net/http'
require 'open3'
require 'openssl'
require 'tmpdir'
require 'uri'
require 'fileutils'

require_relative 'omarchy_translator/providers/base'
require_relative 'omarchy_translator/providers/llm'
require_relative 'omarchy_translator/providers/deepl'
require_relative 'omarchy_translator/providers/claude'
require_relative 'omarchy_translator/providers/claude_code'
require_relative 'omarchy_translator/config'

# Translation for the Omarchy bar widget.
module OmarchyTranslator
  class Error < StandardError; end
  class SetupError < Error; end

  # Canonical (DeepL) codes; each provider maps them to its own wire format.
  TARGET_LANGUAGES = {
    'AR' => 'Arabic', 'BG' => 'Bulgarian', 'CS' => 'Czech', 'DA' => 'Danish',
    'DE' => 'German', 'EL' => 'Greek', 'EN-GB' => 'English (UK)', 'EN-US' => 'English (US)',
    'ES' => 'Spanish', 'ES-419' => 'Spanish (Latin America)', 'ET' => 'Estonian',
    'FI' => 'Finnish', 'FR' => 'French', 'HE' => 'Hebrew', 'HU' => 'Hungarian',
    'ID' => 'Indonesian', 'IT' => 'Italian', 'JA' => 'Japanese', 'KO' => 'Korean',
    'LT' => 'Lithuanian', 'LV' => 'Latvian', 'NB' => 'Norwegian', 'NL' => 'Dutch',
    'PL' => 'Polish', 'PT-BR' => 'Portuguese (Brazil)', 'PT-PT' => 'Portuguese (Portugal)',
    'RO' => 'Romanian', 'RU' => 'Russian', 'SK' => 'Slovak', 'SL' => 'Slovenian',
    'SV' => 'Swedish', 'TH' => 'Thai', 'TR' => 'Turkish', 'UK' => 'Ukrainian',
    'VI' => 'Vietnamese', 'ZH-HANS' => 'Chinese (Simplified)', 'ZH-HANT' => 'Chinese (Traditional)'
  }.freeze

  # Every bare language plus the regional variants, so the source can be as specific as the target.
  SOURCE_LANGUAGES = TARGET_LANGUAGES.each_with_object({}) do |(code, name), langs|
    base = code.split('-').first
    langs[base] ||= name.sub(/ \(.*\)\z/, '')
  end.merge(TARGET_LANGUAGES).freeze

  DEFAULT_TARGET = 'PT-BR'
  DEFAULT_SOURCE = 'EN'

  # Soft hyphen, zero-width chars and BOM that PDFs and web pages leak into copied text.
  INVISIBLE_CHARS = /[­​-‍⁠﻿]/

  def self.normalize(text)
    text.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
        .gsub(/\r\n?|[\u2028\u2029]/, "\n")
        .gsub(INVISIBLE_CHARS, '')
        .gsub(/[\p{Cc}&&[^\n\t]]/, '')
        .then { |cleaned| join_hyphenated_wraps(cleaned) }
        .split(/\n[[:space:]]*\n/)
        .map { |paragraph| paragraph.gsub(/[[:space:]]+/, ' ').strip }
        .reject(&:empty?)
        .join("\n\n")
  end

  HYPHENATED_WRAP = /(\p{L}+)-[ \t]*\n[ \t]*(\p{Ll}\p{L}*)/

  # A word split across lines ("transla-\ntion") is rejoined. The hyphen stays for a
  # compound: a one-letter prefix ("e-\nmail") or one written with a hyphen elsewhere in
  # the text. Without a dictionary a lone "well-\nknown" can't be told apart from a split word.
  def self.join_hyphenated_wraps(text)
    text.gsub(HYPHENATED_WRAP) do
      head, tail = Regexp.last_match.captures
      compound = head.length == 1 || text.include?("#{head}-#{tail}")
      compound ? "#{head}-#{tail}" : "#{head}#{tail}"
    end
  end

  NETWORK_ERRORS = [
    SocketError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
  ].freeze

  PROVIDERS = [DeepL, Claude, ClaudeCode].to_h { |provider| [provider::ID, provider] }.freeze

  DEFAULT_PROVIDER = 'claude-code'
end

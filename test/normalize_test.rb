# frozen_string_literal: true

require_relative 'test_helper'

class NormalizeTest < Minitest::Test
  def normalize(text) = OmarchyTranslator.normalize(text)

  def test_joins_wrapped_lines
    assert_equal 'The quick brown fox jumps', normalize("The quick\nbrown fox\n  jumps\n")
  end

  def test_keeps_paragraphs
    assert_equal "First one.\n\nSecond one.", normalize("First\none.\n\n \n\nSecond\none.")
  end

  def test_rejoins_hyphenated_wraps
    assert_equal 'a translation here', normalize("a transla-\ntion here")
  end

  def test_keeps_hyphen_in_compounds
    assert_equal 'an e-mail', normalize("an e-\nmail")
    assert_equal 'a well-known, well-known name', normalize("a well-\nknown, well-known name")
  end

  def test_keeps_hyphen_before_capitalized_word
    assert_equal 'well- Known', normalize("well-\nKnown")
  end

  def test_handles_windows_line_endings
    assert_equal "One two\n\nThree", normalize("One\r\ntwo\r\n\r\nThree")
  end

  def test_removes_invisible_characters
    assert_equal 'zero width soft hyphen', normalize("ze​ro width so­ft\u0007 hy﻿phen")
  end

  def test_keeps_accents_and_punctuation
    text = 'Olá, você está bem? — Ça va! «sí» 日本語。'

    assert_equal text, normalize(text)
  end

  def test_whitespace_only_becomes_empty
    assert_equal '', normalize(" \n\t \n ")
  end
end

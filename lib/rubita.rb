# frozen_string_literal: true

require "ripper"

require_relative "rubita/version"
require_relative "rubita/transpiler"

module Rubita
  class Error < StandardError; end

  def self.transpile(source)
    Transpiler.new.transpile(source)
  end
end

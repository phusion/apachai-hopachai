#!/usr/bin/env ruby
# encoding: utf-8

DADEROOT = File.absolute_path(File.dirname(__FILE__) + "/..")

class DockerfilePreprocessor
  def initialize(filename, options)
    @filename = filename
    @options = options
    @pre_statements = []
    @post_statements = []
  end

  def preprocess
    File.open(@filename, "r:utf-8") do |f|
      parse(f)
    end
    @pre_statements.join("\n") <<
      "\n" <<
      auto_statements <<
      @post_statements.join("\n")
  end

private
  def parse(io)
    statement = ""
    while !io.eof?
      line = io.readline.strip
      statement << "#{line}\n"
      if line !~ /\\\Z/
        recognize_statement(statement.strip)
        statement = ""
      end
    end
  end

  def recognize_statement(statement)
    statement =~ /\A(\w+)/
    name = $1
    case name.to_s.upcase
    when "FROM", "MAINTAINER"
      @pre_statements << statement
    when "PREADD", "PRERUN"
      @pre_statements << statement.sub(/^PRE/i, "")
    else
      @post_statements << statement
    end
  end

  def auto_statements
    statements = "ADD #{@options[:app_dir_container_build_path]} /app\n"
    statements << "ADD _dade_integration /var/lib/dade_integration\n"
    statements << "RUN if test -e /var/lib/dade_integration/build; then /var/lib/dade_integration/build; fi\n"
    statements
  end
end

preprocessor = DockerfilePreprocessor.new(ARGV[0], :app_dir_container_build_path => ARGV[1])
puts preprocessor.preprocess

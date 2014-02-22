#!/usr/bin/env ruby
require 'set'
require 'pathname'

# Parse a .gitignore file into a set of glob patterns so that we
# can lookup which files we should ignore.
def parse_gitignore(filename, contents)
  dir = File.dirname(filename)
  result = []
  contents.split(/\r?\n/).each do |pattern|
    if pattern.empty? || pattern =~ /^[ \t]*#/
      # Ignore comments and empty lines.
      next
    end

    pattern = pattern.dup
    # If pattern contains trailing slash, e.g. 'tmp/',
    # of if it ends with an 'all files' glob, e.g. 'tmp/*',
    # then normalize it into just 'tmp'.
    pattern.sub!(/\/+\Z/, "") ||
      pattern.sub!(/\/\*+\Z/, "")

    if pattern =~ /\A\//
      # Pattern contains leading slash, e.g. '/tmp...'.
      result << "#{dir}#{pattern}"
      result << "#{dir}#{pattern}/**"
    else
      # Pattern contains no leading slash, e.g. 'tmp...'.
      result << "#{dir}/#{pattern}"
      result << "#{dir}/#{pattern}/**"
      result << "#{dir}/**/#{pattern}"
      result << "#{dir}/**/#{pattern}/**"
    end
  end
  result
end

def load_and_parse_gitignore(filename)
  parse_gitignore(filename, File.read(filename))
end

# Given a file list obtained from Dir.glob(..., File::FNM_DOTMATCH),
# extract all directory names without statting the filesystem.
def extract_directories(list)
  result = Set.new
  list.each do |path|
    if path =~ /\/\.\Z/
      result << path.sub(/\/\.\Z/, "")
    end
  end
  result
end

# List all files in 'dir' except those specified in .gitignore files.
# This method is optimized to access the filesystem as little as
# possible because VirtualBox Shared Folders are extremely slow.
def list_files(dir)
  dir = Pathname.new(File.absolute_path(dir))

  # Query all files including hidden files and directories.
  full_list = Dir.glob("#{dir}/**/*", File::FNM_DOTMATCH)

  # Find out which ones are directories, without statting the
  # filesystem.
  directories = extract_directories(full_list)

  # Obtain just the normal files. No directories, no .git directories.
  files = full_list.reject do |path|
    path =~ /\/\.\.?\Z/ ||
      path =~ /\/\.git($|\/)/ ||
      directories.include?(path)
  end
  files -= [".", ".."]
  full_list = nil

  # Find all .gitignore files.
  gitignores = files.grep(/(\A|\/)\.gitignore\Z/)

  # Extract ignore patterns.
  ignore_patterns = []
  gitignores.each do |gitignore|
    ignore_patterns.concat(load_and_parse_gitignore(gitignore))
  end
  ignore_patterns.sort!
  ignore_patterns.uniq!

  # Compile final result.
  files.reject! do |path|
    ignore_patterns.any? do |pattern|
      File.fnmatch(pattern, path)
    end
  end

  # TODO: always include files in `git ls-files`,
  # even if they appear in .gitignore.

  # Makes filenames relative to dir.
  files.map! do |path|
    Pathname.new(path).relative_path_from(dir).to_s
  end

  files
end

if $0 == __FILE__
  puts list_files(ARGV[0] || "app")
elsif defined?(RSpec)
  describe "ListFiles" do
    describe "#parse_gitignore" do
      def test(pattern, filename)
        parse_gitignore(filename, pattern)
      end

      it "handles '.bundle' in /app/webui/.gitignore" do
        test(".bundle", "/app/webui/.gitignore").should == [
          "/app/webui/.bundle",
          "/app/webui/.bundle/**",
          "/app/webui/**/.bundle",
          "/app/webui/**/.bundle/**"
        ]
      end

      it "handles 'tmp' in /app/webui/.gitignore" do
        test("tmp", "/app/webui/.gitignore").should == [
          "/app/webui/tmp",
          "/app/webui/tmp/**",
          "/app/webui/**/tmp",
          "/app/webui/**/tmp/**"
        ]
      end

      it "handles 'tmp/' in /app/webui/.gitignore" do
        test("tmp/", "/app/webui/.gitignore").should == [
          "/app/webui/tmp",
          "/app/webui/tmp/**",
          "/app/webui/**/tmp",
          "/app/webui/**/tmp/**"
        ]
      end

      it "handles 'tmp/*' in /app/webui/.gitignore" do
        test("tmp/*", "/app/webui/.gitignore").should == [
          "/app/webui/tmp",
          "/app/webui/tmp/**",
          "/app/webui/**/tmp",
          "/app/webui/**/tmp/**"
        ]
      end

      it "handles 'db/*.sqlite3' in /app/webui/.gitignore" do
        test("db/*.sqlite3", "/app/webui/.gitignore").should == [
          "/app/webui/db/*.sqlite3",
          "/app/webui/db/*.sqlite3/**",
          "/app/webui/**/db/*.sqlite3",
          "/app/webui/**/db/*.sqlite3/**"
        ]
      end

      it "handles '/.bundle' in /app/webui/.gitignore" do
        test("/.bundle", "/app/webui/.gitignore").should == [
          "/app/webui/.bundle",
          "/app/webui/.bundle/**"
        ]
      end

      it "handles '/tmp' in /app/webui/.gitignore" do
        test("/tmp", "/app/webui/.gitignore").should == [
          "/app/webui/tmp",
          "/app/webui/tmp/**"
        ]
      end

      it "handles '/tmp/' in /app/webui/.gitignore" do
        test("/tmp/", "/app/webui/.gitignore").should == [
          "/app/webui/tmp",
          "/app/webui/tmp/**"
        ]
      end

      it "handles '/tmp/*' in /app/webui/.gitignore" do
        test("/tmp/*", "/app/webui/.gitignore").should == [
          "/app/webui/tmp",
          "/app/webui/tmp/**"
        ]
      end

      it "handles '/db/*.sqlite3' in /app/webui/.gitignore" do
        test("/db/*.sqlite3", "/app/webui/.gitignore").should == [
          "/app/webui/db/*.sqlite3",
          "/app/webui/db/*.sqlite3/**"
        ]
      end
    end
  end
end

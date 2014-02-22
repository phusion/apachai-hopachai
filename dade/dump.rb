#!/usr/bin/env ruby
require 'yaml'
require 'shellwords'

def dump_key(value, name)
  puts "DADEFILE_#{name}=#{Shellwords.escape value}"
end

def dump_dadefile(dadefile)
  dump_key(dadefile['name'], 'NAME')
  dump_key(dadefile['version'], 'VERSION')
  dump_key(dadefile['app_dir']['path'], 'APP_DIR_PATH')
  dump_key(dadefile['app_dir']['container_build_path'], 'APP_DIR_CONTAINER_BUILD_PATH')
  # dump_key(dadefile['container_build_files']['path'], 'CONTAINER_BUILD_FILES_PATH')
  # dump_key(dadefile['container_build_files']['container_build_path'], 'CONTAINER_BUILD_FILES_CONTAINER_BUILD_PATH')
  dump_key(dadefile['dockerfile_dade'], "DOCKERFILE_DADE")
end

def normalize_cluster_member(member, name = nil)
  member = member.dup

  member['name'] ||= name
  member['version'] ||= '0.1'
  member['app_dir'] ||= '.'
  # member['container_build_files'] ||= '.'
  member['dockerfile_dade'] ||= 'Dockerfile.dade'

  if !member['app_dir'].is_a?(Hash)
    path = member['app_dir'].to_s
    member['app_dir'] = {
      'path' => path,
      'container_build_path' => 'app'
    }
  end
  # if !member['container_build_files'].is_a?(Hash)
  #   path = member['container_build_files'].to_s
  #   member['container_build_files'] = {
  #     'path' => path,
  #     'container_build_path' => 'build'
  #   }
  # end

  member['app_dir']['path'] ||= '.'
  member['app_dir']['container_build_path'] ||= 'app'
  # member['container_build_files']['path'] ||= '.'
  # member['container_build_files']['container_build_path'] ||= 'build'

  if !member['name']
    abort "You must specify a 'name' in your Dadefile."
  end

  member
end

def load_dadefile(filename)
  dadefile = YAML.load_file(filename)
  dadefile = normalize_cluster_member(dadefile)
end

dump_dadefile(load_dadefile(ARGV[0]))

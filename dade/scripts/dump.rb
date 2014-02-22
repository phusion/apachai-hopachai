#!/usr/bin/env ruby
require 'yaml'
require 'shellwords'

def dump_key(value, name)
  if !value.nil?
    puts "DADEFILE_#{name}=#{Shellwords.escape value}"
  end
end

def dump_array(value, name)
  if value
    str = value.join(" ")
    puts "DADEFILE_#{name}=#{Shellwords.escape str}"
  end
end

def dump_dadefile(dadefile)
  dump_key(dadefile['name'], 'NAME')
  dump_key(dadefile['version'], 'VERSION')
  dump_key(dadefile['app_dir']['path'], 'APP_DIR_PATH')
  dump_key(dadefile['app_dir']['build_path'], 'APP_DIR_BUILD_PATH')
  dump_key(dadefile['image_resources_dir']['path'], 'IMAGE_RESOURCES_DIR_PATH')
  dump_key(dadefile['image_resources_dir']['build_path'], 'IMAGE_RESOURCES_DIR_BUILD_PATH')
  dump_key(dadefile['dockerfile_dade'], 'DOCKERFILE_DADE')
  dump_key(dadefile['app_mount_uid'], 'APP_MOUNT_UID')
  dump_key(dadefile['app_mount_gid'], 'APP_MOUNT_GID')
  dump_key(dadefile['privileged'], 'PRIVILEGED')
  dump_array(dadefile['port_forwards'], 'PORT_FORWARDS')
  dump_key(dadefile['docker_run_options'], 'DOCKER_RUN_OPTIONS')
end

def to_string_or_nil(value)
  if value.nil?
    nil
  else
    value.to_s
  end
end

def normalize_cluster_member(member, name = nil)
  member = member.dup

  if !member['app_dir'].is_a?(Hash)
    path = to_string_or_nil(member['app_dir'])
    member['app_dir'] = { 'path' => path }
  end
  if !member['image_resources_dir'].is_a?(Hash)
    path = to_string_or_nil(member['image_resources_dir'])
    member['image_resources_dir'] = { 'path' => path }
  end

  member['name'] ||= name
  member['version'] ||= '0.1'
  member['app_dir']['path'] ||= '.'
  member['app_dir']['build_path'] ||= 'app'
  member['image_resources_dir']['build_path'] ||= 'resources'
  member['dockerfile_dade'] ||= 'Dockerfile.dade'

  if !member['name']
    abort "You must specify a 'name' in your Dadefile."
  end

  member
end

def load_dadefile(filename)
  dadefile = YAML.load_file(filename)
  if !dadefile.is_a?(Hash)
    abort "This doesn't look like a valid Dadefile."
  end
  dadefile = normalize_cluster_member(dadefile)
end

dump_dadefile(load_dadefile(ARGV[0]))

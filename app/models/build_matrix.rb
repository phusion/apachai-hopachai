class BuildMatrix
  COMBINATORIC_KEYS = ['rvm', 'gemfile', 'jdk', 'node_js', 'env'].freeze

  attr_reader :environments

  def initialize(travis)
    @travis = travis
  end

  def calculate
    @environments = []
    traverse(0, {}, COMBINATORIC_KEYS)
    @environments.sort! do |a, b|
      a.inspect <=> b.inspect
    end
  end

  def self.environment_display_name(env)
    result = []
    env.each_pair do |key, val|
      result << "#{key}=#{val}"
    end
    result.join("; ")
  end

private
  def traverse(level, result, remaining_keys)
    if remaining_keys.empty?
      # We're done traversing a combinatoric path. Saving result.
      @environments << result_to_environment(result)
    else
      # Keep traversing.
      key = remaining_keys.first
      remaining_keys = remaining_keys[1 .. -1]
      values = force_nonempty_array_or_nil(@travis[key])

      if values
        # Traverse the paths for each value.
        values.each do |val|
          subpath_result = result.dup
          subpath_result[key] = val
          traverse(level + 1, subpath_result, remaining_keys)
        end
      else
        # No values for this key, keep traversing without this key.
        traverse(level + 1, result, remaining_keys)
      end
    end
  end

  def force_nonempty_array_or_nil(value)
    if value
      if value.is_a?(Array)
        if value.empty?
          nil
        else
          value
        end
      else
        [value]
      end
    else
      nil
    end
  end

  def result_to_environment(result)
    env = {}
    result = result.dup
    vars = result.delete('env')

    result.each_pair do |key, val|
      env[result_key_to_env_key(key)] = val
    end

    vars.to_s.split(/ +/).each do |var|
      key, val = var.split("=", 2)
      env[key] = val
    end

    env
  end

  def result_key_to_env_key(key)
    "APPA_#{key.upcase}"
  end
end

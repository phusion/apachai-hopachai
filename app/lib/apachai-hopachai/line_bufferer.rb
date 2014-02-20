# encoding: binary

module ApachaiHopachai
  class LineBufferer
    def initialize(&callback)
      @callback = callback
      @buffer = ""
    end

    def add(data)
      @buffer << data
      while index = @buffer.index("\n")
        line = @buffer.slice!(0, index + 1)
        @callback.call(line)
      end
    end

    def close
      if !@buffer.empty?
        @callback.call(@buffer)
      end
      @buffer = nil
    end
  end
end

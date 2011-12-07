module Excon
  class NullInstrumentor
    def self.instrument(name, payload = {})
      yield payload if block_given?
    end
  end
end
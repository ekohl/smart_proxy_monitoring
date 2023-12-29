module Proxy::Monitoring
  class Error < RuntimeError; end
  class NotFound < RuntimeError; end
  class AuthenticationError < RuntimeError; end
  class ConnectionError < RuntimeError; end
end

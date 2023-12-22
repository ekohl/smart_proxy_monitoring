module Proxy::Monitoring
  class UploadQueue
    def queue
      @queue ||= Queue.new
    end
  end
end

module ::Proxy::Monitoring::Zabbix
  class MonitoringResult < Proxy::HttpRequest::ForemanRequest
    def push_result(result)
      send_request(request_factory.create_post('api/v2/monitoring_results', result.to_json))
    end
  end

  class ResultUploader
    include ::Proxy::Log

    attr_reader :semaphore

    def initialize(queue)
      @queue = queue
      @semaphore = Mutex.new
    end

    def monitoring_result
      @monitoring_result ||= MonitoringResult.new
    end

    def upload
      while change = @queue.pop
        with_event_counter('Icinga2 Result Uploader') do
          begin
            monitoring_result.push_result(change)
          rescue Errno::ECONNREFUSED => e
            logger.error "Foreman refused connection when tried to upload monitoring result: #{e.message}"
            sleep 10
          rescue StandardError => e
            logger.error "Error while uploading monitoring results to Foreman: #{e.message}"
            sleep 1
            retry
          end
        end
      end
    end

    def start
      @thread = Thread.new { upload }
      @thread.abort_on_exception = true
      @thread
    end

    def stop
      @thread&.terminate
    end

    private

    def symbolize_keys_deep!(h)
      h.each_key do |k|
        ks    = k.to_sym
        h[ks] = h.delete k
        symbolize_keys_deep! h[ks] if h[ks].is_a? Hash
      end
    end

    def add_domain(host)
      domain = Proxy::Monitoring::Plugin.settings.strip_domain
      host = "#{host}#{domain}" unless domain.nil?
      host
    end

    def with_event_counter(log_prefix, interval_count = 100, interval_seconds = 60)
      semaphore.synchronize do
        @counter ||= 0
        @timer ||= Time.now
        if @counter >= interval_count || (Time.now - @timer) > interval_seconds
          status = "#{log_prefix}: Observed #{@counter} events in the last #{(Time.now - @timer).round(2)} seconds."
          status += " #{@queue.length} items queued. #{@queue.num_waiting} threads waiting." unless @queue.nil?
          logger.info status
          @timer = Time.now
          @counter = 0
        end
        @counter += 1
      end
      yield
    end
  end
end

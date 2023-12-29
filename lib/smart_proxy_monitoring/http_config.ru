require 'smart_proxy_monitoring/api'

map '/monitoring' do
  run Proxy::Monitoring::Api
end

module ::Proxy::Monitoring::Zabbix
  class Provider < ::Proxy::Provider
    plugin :monitoring_zabbix, ::Proxy::Monitoring::VERSION

    default_settings url: 'http://localhost/zabbix/api_jsonrpc.php'
    default_settings ignore_version: true
    validate_presence :user, :password
    #capability :config
    #capability :downtime
    #capability :status

    requires :monitoring, ::Proxy::Monitoring::VERSION

    start_services :result_uploader

    load_classes do
      require 'zabbixapi'
      require 'smart_proxy_monitoring_common/monitoring_common'
      require 'smart_proxy_monitoring_zabbix/main'
      require 'smart_proxy_monitoring_zabbix/result_uploader'
    end

    load_dependency_injection_wirings do |container_instance|
      container_instance.singleton_dependency :upload_queue, -> { Queue.new }
      container_instance.dependency :monitoring_provider, (lambda do
        ::Proxy::Monitoring::Zabbix::Main.new(
          queue: container_instance.get_dependency(:upload_queue),
          url: settings.url,
          user: settings.user,
          password: settings.password,
          ignore_version: settings.ignore_version,
        )
      end)
      container_instance.singleton_dependency :result_uploader, (lambda do
        ::Proxy::Monitoring::Zabbix::ResultUploader.new(
          container_instance.get_dependency(:upload_queue),
        )
      end)
    end
  end
end

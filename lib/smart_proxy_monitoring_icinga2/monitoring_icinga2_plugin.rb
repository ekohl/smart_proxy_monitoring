module ::Proxy::Monitoring::Icinga2
  class Plugin < ::Proxy::Provider
    plugin :monitoring_icinga2, ::Proxy::Monitoring::VERSION

    default_settings server: 'localhost'
    default_settings api_port: '5665'
    default_settings verify_ssl: true
    expose_setting :server
    expose_setting :api_user
    capability("config")
    capability("downtime")
    capability("status") unless Proxy::Monitoring::Plugin.settings.collect_status

    requires :monitoring, ::Proxy::Monitoring::VERSION

    start_services :icinga2_initial_importer, :icinga2_api_observer, :icinga2_result_uploader

    load_classes do
      require 'smart_proxy_monitoring_common/monitoring_common'
      require 'smart_proxy_monitoring_icinga2/monitoring_icinga2_main'
      require 'smart_proxy_monitoring_icinga2/monitoring_icinga2_common'
      require 'smart_proxy_monitoring_icinga2/tasks_common'
      require 'smart_proxy_monitoring_icinga2/icinga2_client'
      require 'smart_proxy_monitoring_icinga2/icinga2_initial_importer'
      require 'smart_proxy_monitoring_icinga2/icinga2_api_observer'
      require 'smart_proxy_monitoring_icinga2/icinga2_result_uploader'
    end

    load_dependency_injection_wirings do |container_instance, _settings|
      container_instance.dependency :monitoring_provider, lambda { ::Proxy::Monitoring::Icinga2::Provider.new }
      container_instance.singleton_dependency :icinga2_upload_queue, lambda { Queue.new }
      container_instance.singleton_dependency :icinga2_api_observer, (lambda do
        ::Proxy::Monitoring::Icinga2::Icinga2ApiObserver.new(container_instance.get_dependency(:icinga2_upload_queue))
      end)
      container_instance.singleton_dependency :icinga2_result_uploader, (lambda do
        ::Proxy::Monitoring::Icinga2::Icinga2ResultUploader.new(container_instance.get_dependency(:icinga2_upload_queue))
      end)
      container_instance.singleton_dependency :icinga2_initial_importer, (lambda do
        ::Proxy::Monitoring::Icinga2::Icinga2InitialImporter.new(container_instance.get_dependency(:icinga2_upload_queue))
      end)
    end
  end
end

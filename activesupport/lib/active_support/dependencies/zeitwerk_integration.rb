# frozen_string_literal: true

require "set"
require "active_support/core_ext/string/inflections"
require "zeitwerk"

module ActiveSupport
  module Dependencies
    module ZeitwerkIntegration # :nodoc: all
      module Decorations
        def clear
          Dependencies.unload_interlock do
            Rails.autoloaders.main.reload
          rescue Zeitwerk::ReloadingDisabledError
            raise "reloading is disabled because config.cache_classes is true"
          end
        end

        def constantize(cpath)
          ActiveSupport::Inflector.constantize(cpath)
        end

        def safe_constantize(cpath)
          ActiveSupport::Inflector.safe_constantize(cpath)
        end

        def autoloaded_constants
          Rails.autoloaders.main.unloadable_cpaths
        end

        def autoloaded?(object)
          cpath = object.is_a?(Module) ? real_mod_name(object) : object.to_s
          Rails.autoloaders.main.unloadable_cpath?(cpath)
        end

        def verbose=(verbose)
          l = verbose ? logger || Rails.logger : nil
          Rails.autoloaders.each { |autoloader| autoloader.logger = l }
        end

        def unhook!
          :no_op
        end
      end

      module Inflector
        # Concurrent::Map is not needed. This is a private class, and overrides
        # must be defined while the application boots.
        @overrides = {}

        def self.camelize(basename, _abspath)
          @overrides[basename] || basename.camelize
        end

        def self.inflect(overrides)
          @overrides.merge!(overrides)
        end
      end

      class << self
        def take_over(enable_reloading:)
          setup_autoloaders(enable_reloading)
          freeze_paths
          decorate_dependencies
        end

        private
          def setup_autoloaders(enable_reloading)
            Dependencies.autoload_paths.each do |autoload_path|
              # Zeitwerk only accepts existing directories in `push_dir` to
              # prevent misconfigurations.
              next unless File.directory?(autoload_path)

              autoloader = \
                autoload_once?(autoload_path) ? Rails.autoloaders.once : Rails.autoloaders.main

              autoloader.push_dir(autoload_path)
              autoloader.do_not_eager_load(autoload_path) unless eager_load?(autoload_path)
            end

            if enable_reloading
              Rails.autoloaders.main.enable_reloading
              Rails.autoloaders.main.on_unload do |_cpath, value, _abspath|
                value.before_remove_const if value.respond_to?(:before_remove_const)
              end
            end

            Rails.autoloaders.each(&:setup)
          end

          def autoload_once?(autoload_path)
            Dependencies.autoload_once_paths.include?(autoload_path)
          end

          def eager_load?(autoload_path)
            Dependencies._eager_load_paths.member?(autoload_path)
          end

          def freeze_paths
            Dependencies.autoload_paths.freeze
            Dependencies.autoload_once_paths.freeze
            Dependencies._eager_load_paths.freeze
          end

          def decorate_dependencies
            Dependencies.unhook!
            Dependencies.singleton_class.prepend(Decorations)
          end
      end
    end
  end
end

# Encoding: utf-8
# Cloud Foundry Java Buildpack
# Copyright 2013-2017 the original author or authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fileutils'
require 'java_buildpack/component/versioned_dependency_component'
require 'java_buildpack/jre'
require 'java_buildpack/util/shell'
require 'java_buildpack/util/qualify_path'
require 'open3'
require 'tmpdir'

module JavaBuildpack
  module Jre

    # Encapsulates the detect, compile, and release functionality for the OpenJDK-like memory calculator
    class OpenJDKLikeMemoryCalculator < JavaBuildpack::Component::VersionedDependencyComponent
      include JavaBuildpack::Util

      # (see JavaBuildpack::Component::BaseComponent#compile)
      def compile
        download(@version, @uri) do |file|
          FileUtils.mkdir_p memory_calculator.parent

          if @version[0] < '2'
            unpack_calculator file
          else
            unpack_compressed_calculator file
          end

          memory_calculator.chmod 0o755

          puts "       Loaded Classes: #{class_count @configuration}, " \
               "Threads: #{stack_threads @configuration}, " \
               "JAVA_OPTS: '#{java_opts}'"
        end
      end

      # Returns a fully qualified memory calculation command to be prepended to the buildpack's command sequence
      #
      # @return [String] the memory calculation command
      def memory_calculation_command
        "CALCULATED_MEMORY=$(#{memory_calculation_string(@droplet.root)})"
      end

      # (see JavaBuildpack::Component::BaseComponent#release)
      def release
        @droplet.java_opts.add_preformatted_options '$CALCULATED_MEMORY'
      end

      protected

      # (see JavaBuildpack::Component::VersionedDependencyComponent#supports?)
      def supports?
        true
      end

      private

      def actual_class_count(root)
        (root + '**/*.class').glob.count +
          (root + '**/*.groovy').glob.count +
          (root + '**/*.jar').glob.inject(0) { |a, e| a + archive_class_count(e) }
      end

      def archive_class_count(archive)
        `unzip -l #{archive} | grep '\\(\\.class\\|\\.groovy\\)$' | wc -l`.to_i
      end

      def class_count(configuration)
        configuration['class_count'] || (0.2 * actual_class_count(@application.root)).ceil + 5500
      end

      def java_opts
        ENV['JAVA_OPTS']
      end

      def memory_calculator
        @droplet.sandbox + "bin/java-buildpack-memory-calculator-#{@version}"
      end

      def memory_calculator_tar
        platform = `uname -s` =~ /Darwin/ ? 'darwin' : 'linux'
        @droplet.sandbox + "bin/java-buildpack-memory-calculator-#{platform}"
      end

      def memory_calculation_string(relative_path)
        memory_calculation_string = [qualify_path(memory_calculator, relative_path)]
        memory_calculation_string << '-totMemory=$MEMORY_LIMIT'
        memory_calculation_string << "-stackThreads=#{stack_threads @configuration}"
        memory_calculation_string << "-loadedClasses=#{class_count @configuration}"
        memory_calculation_string << "-vmOptions='#{java_opts}'" if java_opts

        memory_calculation_string.join(' ')
      end

      def stack_threads(configuration)
        configuration['stack_threads']
      end

      def unpack_calculator(file)
        FileUtils.cp_r(file.path, memory_calculator)
      end

      def unpack_compressed_calculator(file)
        shell "tar xzf #{file.path} -C #{memory_calculator.parent} 2>&1"
        FileUtils.mv(memory_calculator_tar, memory_calculator)
      end

    end

  end
end

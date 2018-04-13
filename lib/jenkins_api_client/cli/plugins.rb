#
# Copyright (c) 2012-2013 Kannan Manickam <arangamani.kannan@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
require 'tmpdir'

require 'thor'
require 'thor/group'

BOUNDARY = (rand(1000000).to_s + 'ZZZZZ').freeze

module JenkinsApi
  module CLI
    # This class provides various command line operations related to jobs.
    class Plugins < Thor
      include Thor::Actions
      include Terminal

      desc "list", "List plugins"
      # CLI command to list all jobs in Jenkins or the ones matched by status
      # or a regular expression
      def list
        @client = Helper.setup(parent_options)
        @client.plugin.list_installed.each do |k,v|
          @client.logger.info format(' - %s = %s', k, v)
        end
      end

      desc "disable", "Disable a plugin"
      method_option :plugins, :aliases => "-f",
        :desc => "Array of plugins to disable"
      # CLI command to list all jobs in Jenkins or the ones matched by status
      # or a regular expression
      def disable
        filter = options[:plugins]
        @client = Helper.setup(parent_options)
        @client.plugin.disable filter
      end

      desc "updates", "List available updates"
      def updates
        @client = Helper.setup(parent_options)
        @client.plugin.list_updates.each do |k,v|
          @client.logger.info format(' - %s has new available version %s', k, v)
        end
      end

      desc "install", "Install the plugin"
      method_option :plugin, :aliases => "-P",
        :desc => "Plugin to install"
      method_option :restart, :type => :boolean, :aliases => "-r",
        :desc => "Restart jenkins if needed"
      def install
        @client = Helper.setup(parent_options)
        if options[:offline]
          offline_install options[:plugin]
        else
          @client.plugin.install options[:plugin]
        end
        @client.system.restart! if options[:restart]
      end

      desc "upgrade", "Upgrade pending Jenkins plugin(s)"
      method_option :plugin, :aliases => "-P",
        :desc => "Plugin to install"
      def upgrade
        @client = Helper.setup(parent_options)
        updates = @client.plugin.list_updates

        @client.plugin.url

        if options[:plugin].nil?
          updates.each do |plugin, _version|
            offline_upgrade plugin
          end
        else
          offline_upgrade options[:plugin]
        end
        @client.system.restart! if options[:restart]
      end

      protected

      # Does an offline installation of the plugin. Which means it will download
      # the plugin, on the calling machine, then upload the plugin to the Jenkins
      # server.
      #
      # @param Plugin[String
      #
      def offline_install(plugin)
        if installed? plugin
          @client.logger.error format('The plugin "%s" is already installed', plugin)
          return
        end

        plugins = [plugin].push(dependencies(plugin))
        plugins.uniq!
        plugins.flatten.reverse.each do |item|
          next if installed? item
          @client.logger.info format('Install for plugin %s', item)

          meta = metadata(item)

          if meta.nil?
            @client.logger.warn format('Failed to find metadata for  %s', item)
          else
            url = metadata(item)['url']
            lfile = File.join([Dir.tmpdir, File.basename(url)])

            download url, lfile
            upload lfile
          end
        end
      end

      # Does an offline upgrade of the listed plugin, and it's dependencies.
      # Which means it will download the plugin, on the calling machine, then
      # upload the plugin to the Jenkins server.
      #
      # @param Plugin[String]
      #
      def offline_upgrade(plugin)
        unless installed? plugin
          @client.logger.error format('The plugin %<plugin>s is not installed',
                                      plugin: plugin)
          return
        end

        plugins = [plugin].push(dependencies(plugin))
        plugins.uniq!
        plugins.flatten.reverse.each do |item|
          @client.logger.info format('Upgrading/Installing plugin %<item>s',
                                     item: item)
          meta = metadata(item)
          next if meta.nil?

          url = meta['url']
          lfile = File.join([Dir.tmpdir, File.basename(url)])
          download url, lfile
          upload lfile
        end
      end

      # Gets the list of dependencies for a given plugin.
      #
      # @return plugins [Array] that are a dependencies.
      #
      def dependencies(plugin)
        plugins = []
        metadata(plugin)['dependencies'].each do |dep|
          plugins << dep['name']
        end
        plugins.flatten
      end

      # Returns the plugins metadata as defined by the Jenkins Update
      # Center URL
      #
      # @see Client#api_get_request
      # @see Client#plugin#plugins_metadata
      #
      def metadata(plugin, opts = {})
        force = opts[:force] ? opts[:force] : false
        @meta = @client.plugin.plugins_metadata if @meta.nil? || force
        entry = @meta.select{ |_key, item| item['name'] == plugin }
        entry[plugin]
      end

      # Uploads a HPI/JAR to the Server for offline plugin update/installation
      #
      #
      def upload(plugin)
        post_body = []
        post_body << "--#{BOUNDARY}\r\n"
        post_body << "Content-Disposition: form-data; name=\"user[][image]\"; filename=\"#{File.basename(plugin)}\"\r\n"
        post_body << "Content-Type: application/java-archive  \r\n\r\n"
        post_body << File.read(plugin)
        post_body << "\r\n\r\n--#{BOUNDARY}--\r\n"

        @client.post_data '/pluginManager/uploadPlugin',
                          post_body.join,
                          "multipart/form-data; boundary=#{ BOUNDARY }"
      end

      # Checks if a given plugin is already installed on the server
      #
      # @see Client#plugin#list_installed
      #
      # @return [Boolean]
      #
      def installed?(plugin)
        @client.plugin.list_installed.keys.include? plugin
      end
    end
  end
end

require 'net/http'
require 'json'
require 'open-uri'
require 'fileutils'
require 'pathname'

def fetch(uri_str, limit = 10)
  # You should choose better exception.
  raise ArgumentError, 'HTTP redirect too deep' if limit == 0

  url = URI.parse(uri_str)
  req = Net::HTTP::Get.new(url.path, { 'User-Agent' => 'Mozilla/5.0 (etc...)' })
  response = Net::HTTP.start(url.host, url.port, use_ssl: url.scheme == 'https') do |http|
    http.request(req)
  end
  case response
  when Net::HTTPSuccess     then
    response
  when Net::HTTPRedirection then
    fetch(response['location'], limit - 1)
  else
    response.error!
  end
end

def download(url, filename = nil)
  lfile = filename ? filename : File.basename(url)
  FileUtils.rm lfile if File.exist? lfile
  File.open(lfile, 'wb') do |saved_file|
    open(url, 'rb') do |read_file|
      saved_file.write(read_file.read)
    end
  end

  lfile
end

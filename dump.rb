require 'uri'
require 'faraday'
require 'faraday/detailed_logger'
require 'pp'
require 'timeout'
require 'json'
require 'pry'

def dump(method, params, request, response)
  data = {
    method: method,
    url: request.url,
    headers: extract_headers(request),
    params: params.to_h,
  }

  timestamp = Time.now.strftime("%Y%m%d-%H%M%S-%N")
  random = "%010d" % rand(10**10)
  basename = File.join("dump", "#{timestamp}-#{random}")

  if response
    data[:response] = {
      status: response.status,
      headers: response.headers,
    }
    if response.body
      data[:response][:length] = response.body.length
      File.open("#{basename}.response", "w") do |fh|
        fh.write(response.body)
      end
    end
  end

  File.open("#{basename}.log", "w") do |fh|
    fh.puts(data.pretty_inspect)
  end

  return 404
end

REMOVE_HEADERS = %w(
  version
  x-real-ip
  x-forwarded-for
  x-forwarded-proto
)

def extract_headers(request)
  return request.env.map do |key, value|
    next if value.nil?
    next unless key =~ /^HTTP_/
    name = $'.downcase.gsub('_', '-')

    next if REMOVE_HEADERS.include?(name)
    [name, value]
  end.compact.to_h
end

$http_cache = {}

BLACKLIST = %w(
  localhost
  janus.
  maki.
  192.168.
  127.
)

def faraday_for(uri)
  cache_key = [uri.scheme, uri.host, uri.port]
  return $http_cache[cache_key] || make_faraday_for(uri)
end

def make_faraday_for(uri)
  Faraday.new("#{uri.scheme}://#{uri.host}:#{uri.port}") #do |faraday|
    #faraday.request  :url_encoder
    #faraday.response :detailed_logger
    #faraday.adapter  Faraday.default_adapter
  #end
end

def proxy_forward(method, request)
  uri = URI.parse(request.url)

  headers = extract_headers(request)
  #headers['x-rblgsdp'] = '1'

  # avoid accidental loops
  if BLACKLIST.any? { |prefix| uri.host.start_with?(prefix) }
    return nil
  elsif request.env['HTTP_X_RBLGSDP'] == '1'
    raise "Rejecting looped request"
  end

  Timeout.timeout(10) do
    http = faraday_for(uri)

    if method == :get
      return http.get(uri) do |req|
        req.headers = headers
      end
    elsif method == :post
      request.body.rewind
      return http.post(uri) do |req|
        req.body = request.body.read
        p req.body
        req.headers = headers
      end
    else
      raise "Unknown method: #{method.inspect}"
    end
  end
rescue Timeout::Error
  return nil
end

def response_headers(response)
  headers = response.headers.map { |k, v| [k.downcase, v] }.to_h
  headers.delete('transfer-encoding') if headers['transfer-encoding'] == 'chunked'
  return headers
end

get '/rest/*' do
  response = proxy_forward(:get, request)
  dump(:get, params, request, response)

  return 404 unless response
  return [response.status, response_headers(response), response.body]
end

post '/rest/*' do
  response = proxy_forward(:post, request)
  dump(:post, params, request, response)

  return 404 unless response
  return [response.status, response_headers(response), response.body]
end

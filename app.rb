require 'bundler/setup'

require 'sinatra'

post '/rest/sdp/v7.0/initservices' do
  time = (Time.now.to_f * 1000).round
  headers('x-server-time' => time.to_s)
  return File.read('replies/initservices.json')
end

# For debugging / reverse engineering:
#load 'dump.rb'

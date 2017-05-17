$stdout.sync = $stderr.sync = true
require './app'

run Sinatra::Application

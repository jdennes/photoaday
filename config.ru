require 'sinatra'

set :environment, :production

require 'photoaday'

run Sinatra::Application
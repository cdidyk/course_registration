require 'sinatra'
require 'stripe'
require 'yaml'

require 'sinatra/reloader' if development?

Stripe.api_key = YAML.load_file File.join(File.dirname(__FILE__), "config/stripe.yml")


get "/courses" do
  haml :courses
end

post "/register" do
  params
end

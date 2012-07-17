require 'sinatra'
require 'stripe'
require 'yaml'

require 'sinatra/reloader' if development?

Stripe.api_key = YAML.load_file File.join(File.dirname(__FILE__), "config/stripe.yml")

get "/courses" do
  haml :courses
end

post "/register" do
  total = "$#{PriceCalculator.new(params[:courses]).total}"
  haml :register, locals: {courses: params[:courses], total: total}
end

post "/finalize" do
  params
end


class PriceCalculator
  attr_reader :courses

  def initialize courses
    @courses = courses
  end

  def total
    # discount logic is dealt with here
    36.95
  end
end

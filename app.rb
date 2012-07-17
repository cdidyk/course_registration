require 'sinatra'
require 'stripe'
require 'yaml'
require 'haml'

require 'sinatra/reloader' if development?

Stripe.api_key = YAML.load_file(File.join(File.dirname(__FILE__), "config/stripe.yml"))['private_key']

helpers do
  include Rack::Utils
  alias_method :h, :escape

  def display_money cents
    "$#{cents/100.0}"
  end
end

get "/courses" do
  haml :courses
end

post "/register" do
  courses = params[:courses]
  haml :register, locals: {courses: courses, total: PriceCalculator.new(courses).total}
end

post "/finalize" do
  charge =
    Stripe::Charge.
      create(amount: params[:total],
             currency: "usd",
             card: params[:stripeToken],
             description: "#{params[:name]}: #{params[:courses]}")
  haml :confirmation, locals: {name: params[:name], email: params[:email], phone: params[:phone], courses: params[:courses].split(','), total: charge.amount}
end


class PriceCalculator
  attr_reader :courses

  def initialize courses
    @courses = courses
  end

  #NOTE in cents
  def total
    # discount logic is dealt with here
    3695
  end
end

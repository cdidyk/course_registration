require 'sinatra'
require 'stripe'
require 'yaml'

require 'sinatra/reloader' if development?

Stripe.api_key = YAML.load_file File.join(File.dirname(__FILE__), "config/stripe.yml")

helpers do
  def display_money cents
    "$#{cents/100.0}"
  end
end

get "/courses" do
  haml :courses
end

post "/register" do
  haml :register, locals: {courses: params[:courses], total: PriceCalculator.new(params[:courses]).total}
end

post "/finalize" do
  params
  # charge =
  #   Stripe::Charge.
  #     create(amount: 1000,
  #            currency: "usd",
  #            card: token,
  #            description: "payinguser@example.com")
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

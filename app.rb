require 'sinatra'
require 'stripe'
require 'yaml'
require 'haml'
require 'action_mailer'

require 'sinatra/reloader' if development?


configure do
  if production?
    # intentionally blank...for now
  else
    Stripe.api_key = YAML.load_file(File.join(File.dirname(__FILE__), "config/stripe.yml"))['private_key']
    ActionMailer::Base.delivery_method = :file
    ActionMailer::Base.logger = Logger.new(STDOUT)
    ActionMailer::Base.perform_deliveries = true
    ActionMailer::Base.raise_delivery_errors = true
    ActionMailer::Base.view_paths = File.join Sinatra::Application.root, 'views'
  end
end

helpers do
  include Rack::Utils
  alias_method :h, :escape

  def display_money cents
    MoneyFormatter.display cents
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
  @registrant = OpenStruct.new name: params[:name], email: params[:email], phone: params[:phone], courses: params[:courses].split(','), amount_paid: charge.amount, stripe_charge_id: charge.id, event: "2012 Tai Chi Chuan Festival" #Registrant.create params[:registrant]
  UserMailer.registration_confirmation(@registrant).deliver
  haml :confirmation, locals: {name: params[:name], email: params[:email], phone: params[:phone], courses: params[:courses].split(','), total: charge.amount}
end

class UserMailer < ActionMailer::Base
  default from: "no-reply@shaolinstpete.com"

  def registration_confirmation registrant
    @registrant = registrant
    @amount_paid = MoneyFormatter.display registrant.amount_paid
    mail to: registrant.email, subject: "#{registrant.event} registration confirmation"
  end
end

# class Registrant
#   def self.create
#   end
# end

class MoneyFormatter
  def self.display cents
    "$#{sprintf('%.2f', (cents/100.0))}"
  end
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

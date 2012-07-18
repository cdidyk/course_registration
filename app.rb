require 'sinatra'
require 'stripe'
require 'yaml'
require 'haml'
require 'action_mailer'
require 'mongoid'

require 'sinatra/reloader' if development?


configure do
  Mongoid.load! File.join(File.dirname(__FILE__), "config/mongoid.yml")

  if production?
    # intentionally blank...for now
  else
    Stripe.api_key = YAML.load_file(File.join(File.dirname(__FILE__), "config/stripe.yml"))['private_key']

    ActionMailer::Base.delivery_method = :file
    ActionMailer::Base.logger = Logger.new(STDOUT)
    ActionMailer::Base.perform_deliveries = true
    ActionMailer::Base.raise_delivery_errors = true
    ActionMailer::Base.view_paths = File.join Sinatra::Application.root, 'views'

    Mongoid.logger.level = Logger::DEBUG
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

#TODO change from /finalize to /confirmation ?
post "/finalize" do
  charge =
    Stripe::Charge.
      create(amount: params[:total],
             currency: "usd",
             card: params[:stripeToken],
             description: "#{params[:name]}: #{params[:courses]}")

  #TODO make params under registration so we can just do: Registration.create params[:registration]
  @registration = Registration.create name: params[:name], email: params[:email], phone: params[:phone], courses: params[:courses].split(','), amount_paid: charge.amount, stripe_charge_id: charge.id, stripe_fee: charge.fee, event: "2012 Tai Chi Chuan Festival"
  UserMailer.registration_confirmation(@registration).deliver
  haml :confirmation, locals: {name: params[:name], email: params[:email], phone: params[:phone], courses: params[:courses].split(','), total: charge.amount}
end



class UserMailer < ActionMailer::Base
  default from: "no-reply@shaolinstpete.com"

  def registration_confirmation registration
    @registration = registration
    @amount_paid = MoneyFormatter.display registration.amount_paid
    mail to: registration.email, subject: "#{registration.event} registration confirmation"
  end
end



class Registration
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String
  field :email, type: String
  field :phone, type: String
  field :amount_paid, type: Integer
  field :stripe_fee, type: Integer
  field :stripe_charge_id, type: String
  field :courses, type: Array
  field :event, type: String

  #NOTE maybe add an event index in the future if helpful
  index({name: 1})
  index({courses: 1})
  index({stripe_charge_id: 1})

end

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
    #TODO discount logic
    3695
  end
end

require 'sinatra'
require 'stripe'
require 'yaml'
require 'haml'
require 'action_mailer'
require 'mongoid'

require 'sinatra/reloader' if development?

configure :development do
  Mongoid.load! File.join(File.dirname(__FILE__), "config/development.mongoid.yml")
  Mongoid.logger.level = Logger::DEBUG

  Stripe.api_key = YAML.load_file(File.join(File.dirname(__FILE__), "config/stripe.yml"))['private_key']

  ActionMailer::Base.delivery_method = :file
  ActionMailer::Base.logger = Logger.new(STDOUT)
  ActionMailer::Base.perform_deliveries = true
  ActionMailer::Base.raise_delivery_errors = true
  ActionMailer::Base.view_paths = File.join Sinatra::Application.root, 'views'
end

configure :production do
  Mongoid.load! File.join(File.dirname(__FILE__), "config/production.mongoid.yml")
  Mongoid.logger.level = Logger::WARN

  Stripe.api_key = YAML.load_file(File.join(File.dirname(__FILE__), "config/stripe.yml"))['private_key']

  ActionMailer::Base.perform_deliveries = true
  ActionMailer::Base.raise_delivery_errors = true
  ActionMailer::Base.view_paths = File.join Sinatra::Application.root, 'views'
end

set :haml, format: :html5

helpers do
  include Rack::Utils
  alias_method :h, :escape

  def display_money cents
    MoneyFormatter.display cents
  end
end

get "/courses" do
  haml :courses, locals: {errors: ""}
end

post "/register" do
  courses = params[:courses]

  if courses.blank?
    haml :courses, locals: {errors: "Please check the boxes by the courses you wish to register for"}
  else
    registration =
      Registration.new(courses: courses,
                       amount_paid: PriceCalculator.new(courses).total)
    haml :register, locals: {errors: "", registration: registration}
  end
end

#TODO change from /finalize to /confirmation ?
post "/finalize" do
  @registration =
    Registration.
      new( params[:registration].
             merge({courses: params[:courses].split(','),
                    event: "2012 Tai Chi Chuan Festival"}) )

  if @registration.valid?
    begin
      charge =
        Stripe::Charge.
          create(amount: params[:registration][:amount_paid],
                 currency: "usd",
                 card: params[:stripeToken],
                 description: "#{params[:registration][:name]}: #{params[:courses]}")

      @registration.amount_paid = charge.amount
      @registration.stripe_charge_id = charge.id
      @registration.stripe_fee = charge.fee
    rescue Stripe::StripeError => e
      return haml(:register, locals: {registration: @registration, errors: e.message})
    end
  else
    return haml(:register, locals: {registration: @registration, errors: @registration.errors.full_messages.uniq.join(", ") })
  end

  if @registration.save
    UserMailer.
      registration_confirmation(@registration).
      deliver

    haml :confirmation, locals: {registration: @registration}
  else
    haml :register, locals: {registration: @registration, errors: @registration.errors.full_messages.uniq.join(", ") }
  end
end

# useful for working on the design of /confirmation
# get "/confirmation" do
#   haml :confirmation, locals: {registration: Registration.last}
# end


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

  validates_presence_of :name, :email, :courses, :event

end

class MoneyFormatter
  def self.display cents
    "$#{sprintf('%.2f', (cents/100.0))}"
  end
end

class PriceCalculator
  attr_reader :courses, :tcc, :ck

  CK_COURSE_LIST = ["Generating Energy Flow",
                    "Cosmic Shower",
                    "Abdominal Breathing",
                    "Merging with the Cosmos"]
  TCC_COURSE_LIST = ["Fundamentals of Tai Chi Chuan",
                     "108-Pattern Yang style Tai Chi Chuan",
                     "Flowing Water Floating Clouds",
                     "Wudang Tai Chi Chuan"]

  # Pricing structure:
  # 1 CK course: $300
  # 1 TCC course: $500
  # 1 CK course + 1 TCC course: $700
  # all CK courses: $1000
  # all TCC courses: $1300
  # everything: $1800
  CK_UNIT_PRICE = 30000
  TCC_UNIT_PRICE = 50000
  ONE_OF_EACH_PRICE = 70000
  ALL_CK_PRICE = 100000
  ALL_TCC_PRICE = 130000
  EVERYTHING_PRICE = 180000

  def initialize courses
    @courses = courses.uniq
    @tcc = @courses.find_all {|c| TCC_COURSE_LIST.include? c }
    @ck = @courses.find_all {|c| CK_COURSE_LIST.include? c }
  end

  #NOTE in cents
  def total
    if tcc.size == 0
      [(ck.size * CK_UNIT_PRICE), ALL_CK_PRICE].min
    elsif ck.size == 0
      [(tcc.size * TCC_UNIT_PRICE), ALL_TCC_PRICE].min
    else
      [one_of_each_strategy, all_ck_strategy, all_tcc_strategy, EVERYTHING_PRICE].min
    end
  end

  def one_of_each_strategy
    course_pairs = [tcc.size, ck.size].min
    sticker_price = ONE_OF_EACH_PRICE * course_pairs

    if tcc.size > ck.size
      sticker_price += (tcc.size - course_pairs) * TCC_UNIT_PRICE
    else
      sticker_price += (ck.size - course_pairs) * CK_UNIT_PRICE
    end

    sticker_price
  end

  def all_ck_strategy
    ALL_CK_PRICE + (tcc.size * TCC_UNIT_PRICE)
  end

  def all_tcc_strategy
    ALL_TCC_PRICE + (ck.size * CK_UNIT_PRICE)
  end
end

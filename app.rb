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

  stripe_keys = YAML.load_file(File.join(File.dirname(__FILE__), "config/stripe.yml"))
  Stripe.api_key = stripe_keys['private_key']
  STRIPE_PUBLIC_KEY = stripe_keys['public_key']

  ActionMailer::Base.delivery_method = :file
  ActionMailer::Base.logger = Logger.new(STDOUT)
  ActionMailer::Base.perform_deliveries = true
  ActionMailer::Base.raise_delivery_errors = true
  ActionMailer::Base.view_paths = File.join Sinatra::Application.root, 'views'
end

configure :production do
  Mongoid.load! File.join(File.dirname(__FILE__), "config/production.mongoid.yml")
  Mongoid.logger.level = Logger::WARN

  stripe_keys = YAML.load_file(File.join(File.dirname(__FILE__), "config/stripe.yml"))
  Stripe.api_key = stripe_keys['private_key']
  STRIPE_PUBLIC_KEY = stripe_keys['public_key']

  ActionMailer::Base.smtp_settings = {
    openssl_verify_mode: "none"
  }
  ActionMailer::Base.perform_deliveries = true
  ActionMailer::Base.raise_delivery_errors = false
  ActionMailer::Base.view_paths = File.join Sinatra::Application.root, 'views'
end

set :haml, format: :html5
set :discounts, false


helpers do
  include Rack::Utils
  alias_method :h, :escape

  def display_money cents
    MoneyFormatter.display cents
  end

  def checked? value
    return nil unless params[:courses]

    params[:courses].include?(value) ? "checked" : nil
  end
end

get "/courses" do
  haml :courses, locals: {errors: ""}
end

post "/register" do
  courses = params[:courses]
  coupon = params[:member_code].blank? ? nil : Coupon.where(code: params[:member_code].downcase).first

  if courses.blank?
    haml :courses, locals: {errors: "Please check the boxes by the courses you wish to register for"}
  elsif coupon.blank? && params[:member_code].present?
    haml :courses, locals: {errors: "The Member Code you entered is invalid. Please enter a valid one or remove the code."}
  else
    price_calc = PriceCalculator.new courses
    coupon ? price_calc.extend(MemberPricing) : price_calc.extend(NonMemberPricing)
    registration =
      Registration.new(courses: courses,
                       coupon: coupon,
                       amount_paid: price_calc.total)
    haml :register, locals: {errors: "", registration: registration}
  end
end

#TODO change from /finalize to /confirmation ?
post "/finalize" do
  courses = params[:courses].split(',')
  coupon = params[:member_code].blank? ? nil : Coupon.where(code: params[:member_code].downcase).first

  @registration =
    Registration.
      new( params[:registration].
             merge({courses: courses,
                    coupon: coupon,
                    event: "2012 Tai Chi Chuan Festival"}) )

  price_calc = PriceCalculator.new courses
  coupon ? price_calc.extend(MemberPricing) : price_calc.extend(NonMemberPricing)

  if @registration.amount_paid != price_calc.total
    @registration.amount_paid = price_calc.total
    return haml(:register, locals: {registration: @registration, errors: "There was an internet hiccup that prevented us from successfully processing your registration. Please try again. (Don't worry, you weren't billed.)"})
  end

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

    UserMailer.
      registration_notice(@registration).
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

  def registration_notice registration
    @registration = registration
    @amount_paid = MoneyFormatter.display registration.amount_paid
    mail to: "cdidyk@gmail.com", subject: "New Course Registration -#{registration.name}"
  end
end


class Coupon
  include Mongoid::Document
  include Mongoid::Timestamps

  field :code, type: String
  field :description, type: String

  has_many :registrations

  index({code: 1})

  validates_presence_of :code
  validates_uniqueness_of :code

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

  belongs_to :coupon

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

module MemberPricing
  # Member pricing structure:
  # 1 CK course: $300
  # 1 TCC course: $500
  # 1 CK course + 1 TCC course: $700
  # all CK courses: $1000
  # all TCC courses: $1300
  # everything: $1800
  def prices
    { ck_unit_price: 30000,
      tcc_unit_price: 50000,
      one_of_each_price: 70000,
      all_ck_price: 100000,
      all_tcc_price: 130000,
      everything_price: 180000 }
  end
  # CK_UNIT_PRICE = 30000
  # TCC_UNIT_PRICE = 50000
  # ONE_OF_EACH_PRICE = 70000
  # ALL_CK_PRICE = 100000
  # ALL_TCC_PRICE = 130000
  # EVERYTHING_PRICE = 180000
end

module NonMemberPricing
  # Non-member pricing structure:
  # 1 CK course: $300
  # 1 TCC course: $1000
  # 1 CK course + 1 TCC course: $1200
  # all CK courses: $1000
  # all TCC courses: $2600
  # everything: $3000
  def prices
    { ck_unit_price: 30000,
      tcc_unit_price: 100000,
      one_of_each_price: 120000,
      all_ck_price: 100000,
      all_tcc_price: 260000,
      everything_price: 300000 }
  end
  # CK_UNIT_PRICE = 30000
  # TCC_UNIT_PRICE = 100000
  # ONE_OF_EACH_PRICE = 120000
  # ALL_CK_PRICE = 100000
  # ALL_TCC_PRICE = 260000
  # EVERYTHING_PRICE = 300000
end

#NOTE this class must extend a Pricing module to work
class PriceCalculator
  attr_reader :courses, :tcc, :ck, :coupon

  CK_COURSE_LIST = ["Generating Energy Flow",
                    "Cosmic Shower",
                    "Abdominal Breathing",
                    "Merging with the Cosmos"]
  TCC_COURSE_LIST = ["Fundamentals of Tai Chi Chuan",
                     "108-Pattern Yang style Tai Chi Chuan",
                     "Flowing Water Floating Clouds",
                     "Wudang Tai Chi Chuan"]

  def initialize courses
    @courses = courses.uniq
    @tcc = @courses.find_all {|c| TCC_COURSE_LIST.include? c }
    @ck = @courses.find_all {|c| CK_COURSE_LIST.include? c }
  end

  #NOTE in cents
  def total
    if !settings.discounts
      return (ck.size * prices[:ck_unit_price]) + (tcc.size * prices[:tcc_unit_price])
    end

    if tcc.size == 0
      [(ck.size * prices[:ck_unit_price]), prices[:all_ck_price]].min
    elsif ck.size == 0
      [(tcc.size * prices[:tcc_unit_price]), prices[:all_tcc_price]].min
    else
      [one_of_each_strategy, all_ck_strategy, all_tcc_strategy, prices[:everything_price]].min
    end
  end

  def one_of_each_strategy
    course_pairs = [tcc.size, ck.size].min
    sticker_price = prices[:one_of_each_price] * course_pairs

    if tcc.size > ck.size
      sticker_price += (tcc.size - course_pairs) * prices[:tcc_unit_price]
    else
      sticker_price += (ck.size - course_pairs) * prices[:ck_unit_price]
    end

    sticker_price
  end

  def all_ck_strategy
    prices[:all_ck_price] + (tcc.size * prices[:tcc_unit_price])
  end

  def all_tcc_strategy
    prices[:all_tcc_price] + (ck.size * prices[:ck_unit_price])
  end
end

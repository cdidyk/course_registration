require File.join( File.dirname(__FILE__), '..', 'app' )
require 'rspec'
require 'rack/test'
require 'database_cleaner'

set :environment, :test

configure :test do
  Mongoid.load! File.join(File.dirname(__FILE__), '..', 'config/mongoid.yml')

  RSpec.configure do |config|
    config.mock_with :rspec

    config.before(:suite) do
      DatabaseCleaner[:mongoid].strategy = :truncation
    end

    config.before(:each) do
      DatabaseCleaner.start
    end

    config.after(:each) do
      DatabaseCleaner.clean
    end
  end
end

describe "/finalize" do
  include Rack::Test::Methods
  let(:app) { Sinatra::Application }


  let(:params) {
    { name: 'Paul Funktower',
      email: 'pfunk@example.com',
      phone: '(555) 123-1234',
      total: '30000',
      courses: 'Generating Energy Flow,The Essence of All Tai Chi Chuan',
      stripeToken: 'abc123'
    }
  }
  let(:stripe_charge) { stub Stripe::Charge, amount: 30000, id: 'jb007', fee: 900 }
  let(:registration) { stub Registration }

  before :each do
    Stripe::Charge.stub create: stripe_charge
    Registration.stub create: registration
    UserMailer.stub registration_confirmation: stub("Mail", deliver: nil)
  end

  it "should create a Stripe Charge" do
    Stripe::Charge.
      should_receive(:create).
      with(amount: '30000',
           currency: 'usd',
           card: 'abc123',
           description: 'Paul Funktower: Generating Energy Flow,The Essence of All Tai Chi Chuan').
      and_return stripe_charge

    post '/finalize', params
  end

  it "should create a Registration" do
    Registration.unstub :create

    post '/finalize', params

    Registration.count.should == 1
    Registration.first.tap do |reg|
      reg.name.should == "Paul Funktower"
      reg.email.should == "pfunk@example.com"
      reg.phone.should == "(555) 123-1234"
      reg.amount_paid.should == 30000
      reg.stripe_fee.should == 900
      reg.stripe_charge_id.should == 'jb007'
      reg.courses.should == ['Generating Energy Flow', 'The Essence of All Tai Chi Chuan']
      reg.event.should == '2012 Tai Chi Chuan Festival'
    end
  end

  #TODO success vs. failure part
  it "should send the registrant a confirmation email if the Registration succeeds" do
    UserMailer.
      should_receive(:registration_confirmation).
      with(registration).and_return mailer = stub("Mail")
    mailer.
      should_receive(:deliver)

    post '/finalize', params
  end
end

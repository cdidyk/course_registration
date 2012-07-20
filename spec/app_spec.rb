require File.join( File.dirname(__FILE__), '..', 'app' )
require 'rspec'
require 'rack/test'
require 'database_cleaner'

set :environment, :test

configure :test do
  Mongoid.load! File.join(File.dirname(__FILE__), "..", "config/test.mongoid.yml")
  Mongoid.logger.level = Logger::DEBUG

  ActionMailer::Base.delivery_method = :file
  ActionMailer::Base.logger = Logger.new(STDOUT)
  ActionMailer::Base.perform_deliveries = true
  ActionMailer::Base.raise_delivery_errors = true
  ActionMailer::Base.view_paths = File.join Sinatra::Application.root, 'views'


  RSpec.configure do |config|
    config.mock_with :rspec

    config.include Rack::Test::Methods

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
  let(:app) { Sinatra::Application }

  let(:params) {
    { registration: {
        name: 'Paul Funktower',
        email: 'pfunk@example.com',
        phone: '(555) 123-1234',
        amount_paid: '30000' },
      courses: 'Generating Energy Flow,The Essence of All Tai Chi Chuan',
      stripeToken: 'abc123'
    }
  }
  let(:stripe_charge) { stub Stripe::Charge, amount: 30000, id: 'jb007', fee: 900 }
  let(:registration) {
    Registration.new(
         name: "name",
         email: "email",
         phone: "phone",
         courses: ["Some", "Courses"],
         event: "2012 Tai Chi Chuan Festival",
         amount_paid: 0)
  }

  before :each do
    Stripe::Charge.stub create: stripe_charge
    registration.stub save: true
    Registration.stub new: registration
    UserMailer.stub registration_confirmation: stub("Mail", deliver: nil)
  end

  context "when the Registration info is valid" do
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

    context "and the Stripe charge is successful" do
      it "should create a Registration" do
        Registration.unstub :new

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

      context "and the Registration is saved successfully" do
        it "should send the registrant a confirmation email if the Registration succeeds" do
          UserMailer.
            should_receive(:registration_confirmation).
            with(registration).and_return mailer = stub("Mail")
          mailer.
            should_receive(:deliver)

          post '/finalize', params
        end
      end

      context "but saving the Registration fails" do
        before :each do
          registration.stub save: false
        end

        it "should not email the registrant" do
          UserMailer.should_not_receive(:registration_confirmation)
          post '/finalize', params
        end
      end
    end

    context "but the Stripe charge fails" do
      before :each do
        Stripe::Charge.
          stub(:create).
          and_raise Stripe::CardError.new("Your card number is incorrect", "", "card_declined")
      end

      it "should not save the Registration" do
        registration.should_not_receive(:save)
        post '/finalize', params
      end
    end
  end

  context "when the Registration info is invalid" do
    before :each do
      registration.stub valid?: false
    end

    it "should not create a Stripe charge" do
      Stripe::Charge.should_not_receive(:create)
      post '/finalize', params
    end

    it "should not save the registration" do
      registration.should_not_receive(:save)
      post '/finalize', params
    end
  end
end

describe PriceCalculator do
  let(:app) { Sinatra::Application }
  let(:courses) {
    { energy_flow: 'Generating Energy Flow',
      shower: 'Cosmic Shower',
      ab: 'Abdominal Breathing',
      cosmos: 'Merging with the Cosmos',
      tcc: 'Fundamentals of Tai Chi Chuan',
      yang: '108-Pattern Yang style Tai Chi Chuan',
      chen: 'Flowing Water Floating Clouds',
      wudang: 'Wudang Tai Chi Chuan' }
  }

  describe "#total" do
    context "Chi Kung only" do
      it "should be $300 for 1 Chi Kung course" do
        PriceCalculator.
          new([courses[:energy_flow]]).
          total.should == 30000
      end

      it "should be $600 for 2 Chi Kung courses" do
        PriceCalculator.
          new([courses[:energy_flow], courses[:shower]]).
          total.should == 60000
      end

      it "should be $900 for 3 Chi Kung courses" do
        PriceCalculator.
          new([courses[:energy_flow], courses[:shower], courses[:ab]]).
          total.should == 90000
      end

      it "should be $1000 for all 4 Chi Kung courses" do
        PriceCalculator.
          new([courses[:energy_flow], courses[:shower], courses[:ab], courses[:cosmos]]).
          total.should == 100000
      end
    end

    context "Tai Chi Chuan only" do
      it "should be $500 for 1 Tai Chi Chuan course" do
        PriceCalculator.
          new([courses[:tcc]]).
          total.should == 50000
      end

      it "should be $1000 for 2 Tai Chi Chuan courses" do
        PriceCalculator.
          new([courses[:tcc], courses[:wudang]]).
          total.should == 100000
      end

      it "should be $1300 for 3 Tai Chi Chuan courses" do
        PriceCalculator.
          new([courses[:tcc], courses[:yang], courses[:wudang]]).
          total.should == 130000
      end

      it "should be $1300 for all 4 Tai Chi Chuan courses" do
        PriceCalculator.
          new([courses[:tcc], courses[:yang], courses[:chen], courses[:wudang]]).
          total.should == 130000
      end
    end

    context "combinations of Chi Kung and Tai Chi Chuan courses" do
      it "should be $700 for 1 Chi Kung course and 1 Tai Chi Chuan course" do
        PriceCalculator.
          new([courses[:energy_flow],
               courses[:tcc]]).
          total.should == 70000
      end

      it "should be $1200 for 1 Chi Kung course and 2 Tai Chi Chuan courses" do
        PriceCalculator.
          new([courses[:energy_flow],
               courses[:tcc], courses[:wudang]]).
          total.should == 120000
      end

      it "should be $1600 for 1 Chi Kung course and 3 Tai Chi Chuan courses" do
        PriceCalculator.
          new([courses[:energy_flow],
               courses[:tcc], courses[:wudang], courses[:chen]]).
          total.should == 160000
      end

      it "should be $1600 for 1 Chi Kung course and all 4 Tai Chi Chuan courses" do
        PriceCalculator.
          new([courses[:energy_flow],
               courses[:tcc], courses[:wudang], courses[:chen], courses[:yang]]).
          total.should == 160000
      end

      it "should be $1000 for 2 Chi Kung courses and 1 Tai Chi Chuan course" do
        PriceCalculator.
          new([courses[:energy_flow], courses[:cosmos],
               courses[:tcc]]).
          total.should == 100000
      end

      it "should be $1400 for 2 Chi Kung courses and 2 Tai Chi Chuan courses" do
        PriceCalculator.
          new([courses[:energy_flow], courses[:cosmos],
               courses[:wudang], courses[:chen]]).
          total.should == 140000
      end

      it "should be $1800 for 2 Chi Kung courses and 3 Tai Chi Chuan courses" do
        PriceCalculator.
          new([courses[:energy_flow], courses[:cosmos],
               courses[:tcc], courses[:wudang], courses[:chen]]).
          total.should == 180000
      end

      it "should be $1800 for 2 Chi Kung courses and all 4 Tai Chi Chuan courses" do
        PriceCalculator.
          new([courses[:energy_flow], courses[:cosmos],
               courses[:tcc], courses[:yang], courses[:wudang], courses[:chen]]).
          total.should == 180000
      end

      it "should be $1300 for 3 Chi Kung courses and 1 Tai Chi Chuan course" do
        PriceCalculator.
          new([courses[:energy_flow], courses[:shower], courses[:ab],
               courses[:tcc]]).
          total.should == 130000
      end

      it "should be $1700 for 3 Chi Kung courses and 2 Tai Chi Chuan courses" do
        PriceCalculator.
          new([courses[:energy_flow], courses[:shower], courses[:ab],
               courses[:tcc], courses[:wudang]]).
          total.should == 170000
      end

      it "should be $1800 for 3 Chi Kung courses and 3 Tai Chi Chuan courses" do
        PriceCalculator.
          new([courses[:energy_flow], courses[:shower], courses[:ab],
               courses[:tcc], courses[:wudang], courses[:chen]]).
          total.should == 180000
      end

      it "should be $1800 for 3 Chi Kung courses and all 4 Tai Chi Chuan courses" do
        PriceCalculator.
          new([courses[:energy_flow], courses[:shower], courses[:ab],
               courses[:tcc], courses[:wudang], courses[:chen], courses[:yang]]).
          total.should == 180000
      end

      it "should be $1500 for all 4 Chi Kung courses and 1 Tai Chi Chuan course" do
        PriceCalculator.
          new([courses[:energy_flow], courses[:shower], courses[:ab], courses[:cosmos],
               courses[:tcc]]).
          total.should == 150000
      end

      it "should be $1800 for all 4 Chi Kung courses and 2 Tai Chi Chuan courses" do
        PriceCalculator.
          new([courses[:energy_flow], courses[:shower], courses[:ab], courses[:cosmos],
               courses[:tcc], courses[:yang]]).
          total.should == 180000
      end

      it "should be $1800 for all 4 Chi Kung courses and 3 Tai Chi Chuan courses" do
        PriceCalculator.
          new([courses[:energy_flow], courses[:shower], courses[:ab], courses[:cosmos],
               courses[:tcc], courses[:yang], courses[:chen]]).
          total.should == 180000
      end

      it "should be $1800 for all 4 Chi Kung courses and all 4 Tai Chi Chuan courses" do
        PriceCalculator.
          new(courses.values).
          total.should == 180000
      end
    end

    it "should ignore courses it doesn't recognize" do
      PriceCalculator.
        new([courses[:energy_flow], "Wishful Thinking"]).
        total.should == 30000
    end
  end
end

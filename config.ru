require 'rubygems'
require 'bundler'

Bundler.require

require './course_registration'
run Sinatra::Application

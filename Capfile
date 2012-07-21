load 'deploy' if respond_to? :namespace

require 'bundler/capistrano'

set :user, "layman"
set :password, "password"
set :use_sudo, false

set :scm, :git
set :bundle_without, [:development, :test]

role :web, "shaolinstpete.com"
role :app, "shaolinstpete.com"
role :db, "shaolinstpete.com", primary: true, no_release: true

set :application, "course_registration"
set :repository, "git://github.com/cdidyk/course_registration.git"
set :deploy_to, "/srv/course_registration"

after "deploy:update_code", "deploy:symlink_configs"

namespace :deploy do
  task :start, roles: :app do
    run "cd #{deploy_to}/current && bundle exec unicorn -E production -c config/unicorn/course_registration_production.conf -D"
  end

  task :stop, roles: :app do
    run "kill -s QUIT `cat #{deploy_to}/shared/pids/unicorn.pid`"
  end

  task :restart, roles: :app, except: { no_release: true } do
    stop
    start
  end

  task :symlink_configs, roles: :app, except: { no_release: true, no_symlink: true } do
    ["production.mongoid.yml"].each do |file|
      run "ln -nsf #{deploy_to}/shared/config/#{file} #{current_release}/config"
    end
  end

  task :migrate do ; end
end

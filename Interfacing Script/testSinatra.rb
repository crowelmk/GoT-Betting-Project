#!/usr/bin/ruby
require 'sinatra'
require 'mysql2'
require 'erb'
Tilt.register Tilt::ERBTemplate, 'html.erb'

# template_path = "test.html.erb"
# template_file = File.read(template_path)

@@client = Mysql2::Client.new(:host => "192.168.91.2",:username => "testuser", :password => "mysqltest", :database => "testBase");

# Interpret erb file
# html_doc = ERB.new(template_file).result(binding)

get '/' do
	erb :'index.html'
end

get '/houseBet' do
	erb :'winHouseBet.html'
end

get '/placeHouseBet/:betName' do
	erb :'takeBetInput.html', :locals => {'betName' => params[:betName]}
end

post '/addHouseBet' do
	require_relative 'testEndToEnd.rb'
	betChoice = params[:betName]
	email = params[:email]
	bet = params[:bet]
	add_house_bet(betChoice, @@client, email, bet)
    redirect '/'
end

get '/deathBet' do
	erb :'winDeathBet.html'
end

get '/placeDeathBet/:betName' do
	erb :'takeDeathBetInput.html', :locals => {'betName' => params[:betName]}
end

post '/addDeathBet' do
	require_relative 'testEndToEnd.rb'
	betChoice = params[:betName]
	email = params[:email]
	bet = params[:bet]
	add_death_bet(betChoice, @@client, email, bet)
    redirect '/'
end

get '/resurrectBet' do
	erb :'winResurrectBet.html'
end

get '/placeResurrectBet/:betName' do
	erb :'takeResurrectBetInput.html', :locals => {'betName' => params[:betName]}
end

post '/addResurrectBet' do
	require_relative 'testEndToEnd.rb'
	betChoice = params[:betName]
	email = params[:email]
	bet = params[:bet]
	add_resurrect_bet(betChoice, @@client, email, bet)
    redirect '/'
end
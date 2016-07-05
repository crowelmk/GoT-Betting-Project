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

get '/lannister' do
	erb :'lannisterBet.html', :locals => {'client' => @@client} 
end

get '/stark' do
	erb :'starkBet.html', :locals => {'client' => @@client} 
end

get '/watch' do
	erb :'nightsWatchBet.html', :locals => {'client' => @@client} 
end

get '/greyjoy' do
	erb :'greyjoylannisterBet.html', :locals => {'client' => @@client} 
end

get '/baratheon' do
	erb :'baratheonBet.html', :locals => {'client' => @@client} 
end

post '/addLannister' do
	require_relative 'testEndToEnd.rb'
	email = params[:email]
	bet = params[:bet]
	puts "Email: #{email}; Bet: #{bet}"
	# add_house_bet("lannister", @@client, email, bet)
    # redirect '/'
end

post '/addStark' do
	require_relative 'testEndToEnd.rb'
	email = params[:email]
	bet = params[:bet]
	puts "Email: #{email}; Bet: #{bet}"
	# add_house_bet("stark", @@client, email, bet)
    # redirect '/'
end

post '/addBaratheon' do
	require_relative 'testEndToEnd.rb'
	email = params[:email]
	bet = params[:bet]
	puts "Email: #{email}; Bet: #{bet}"
	# add_house_bet("baratheon", @@client, email, bet)
    # redirect '/'
end

post '/addGreyjoy' do
	require_relative 'testEndToEnd.rb'
	email = params[:email]
	bet = params[:bet]
	puts "Email: #{email}; Bet: #{bet}"
	# add_house_bet("greyjoy", @@client, email, bet)
    # redirect '/'
end

post '/addWatch' do
	require_relative 'testEndToEnd.rb'
	email = params[:email]
	bet = params[:bet]
	puts "Email: #{email}; Bet: #{bet}"
	# add_house_bet("watch", @@client, email, bet)
    # redirect '/'
end

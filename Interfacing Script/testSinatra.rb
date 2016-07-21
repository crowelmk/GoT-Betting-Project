#!/usr/bin/ruby
require 'sinatra'
require 'mysql2'
require 'erb'
require 'json'
Tilt.register Tilt::ERBTemplate, 'html.erb'

# template_path = "test.html.erb"
# template_file = File.read(template_path)
Mysql2::Client.default_query_options.merge!(:as => :array)
@@client = Mysql2::Client.new(:host => "192.168.91.2",:username => "testuser", :password => "mysqltest", :database => "testBase");

# Interpret erb file
# html_doc = ERB.new(template_file).result(binding)

get '/' do
	erb :'home.html', :locals => {'client' => @@client}
	# erb :'updateChoice.html'
	# erb :'chart.html', :locals => {'client' => @@client}
end

get '/throneBet' do
	erb :'throneBet.html', :locals => {'client' => @@client}
end

get '/deathBet' do
	erb :'deathBet.html', :locals => {'client' => @@client}
end

get '/resurrectBet' do
	erb :'resBet.html', :locals => {'client' => @@client}
end

get '/placeBet/:betCategory&:betChoice' do
	erb :'betInput.html', :locals => {'betCategory' => params[:betCategory], 'betChoice' => params[:betChoice]}
end

post '/addBet' do
	require_relative 'views/testEndToEnd.rb'
	betCategory = params[:betCategory]
	betChoice = params[:betChoice]
	email = params[:email]
	bet = params[:bet]

	case betCategory
	when "throne"
		add_throne_bet(betChoice, @@client, email, bet)
	when "death"
		add_death_bet(betChoice, @@client, email, bet)
	when "resurrect"
		add_resurrect_bet(betChoice, @@client, email, bet)
	else
		puts "Invalid bet!"
	end

	redirect '/'
end

get '/history' do
	erb :'history.html', :locals => {'client' => @@client}
end
post '/obtainBetHistory' do
	require_relative 'views/testEndtoEnd.rb'

	obtain_bet_history(@@client, params[:option], params[:email]).to_json
end
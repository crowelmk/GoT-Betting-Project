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
	# erb :'home.html', :locals => {'client' => @@client}
	# erb :'updateChoice.html'
	# erb :'chart.html', :locals => {'client' => @@client}
	erb :'testUpdatePerson.html', :locals => {'client' => @@client}
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

get '/statistics' do
	erb :'statistics.html', :locals => {'client' => @@client}
end

get '/updateMenu' do
	erb :'updateChoice.html'
end

get '/updatePerson' do
	erb :'updatePerson.html'
end

post '/performPersonUpdate' do
	require_relative 'views/testEndToEnd.rb'

	update_person(@@client, params[:charName], params[:bookNo], params[:houseName], 
		params[:title], params[:isAlive], params[:deathProb], params[:popularity])
	redirect '/updateMenu'
end

get '/updateHouse' do
	erb :'updateHouse.html'
end

post '/performHouseUpdate' do
	require_relative 'views/testEndToEnd.rb'

	update_house(@@client, params[:houseName], params[:bookNo], params[:wonThrone])
	redirect '/updateMenu'
end

get '/deleteEvent' do
	erb :'deleteEvent.html'
end

post '/performDeleteEvent' do
	require_relative 'views/testEndToEnd.rb'

	delete_event(@@client, params[:name], params[:bookNo], params[:eventType])
	redirect '/updateMenu'
end

post '/obtainCharacters' do
	require_relative 'views/testEndtoEnd.rb'
	numChar = params[:numChar]
	amtData = params[:amtData]

	if numChar == "some" && amtData == "some"
		obtain_some_characters_some_data(@@client).to_json
	elsif numChar == "some" && amtData == "all"
		obtain_some_characters_all_data(@@client).to_json
	elsif numChar == "all" && amtData == "some"
		obtain_some_characters_all_data(@@client).to_json
	elsif numChar == "all" && amtData == "all"
		obtain_all_characters_all_data(@@client).to_json
	end
end
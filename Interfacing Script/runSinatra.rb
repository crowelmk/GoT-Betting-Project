#!/usr/bin/ruby
require 'sinatra'
require 'mysql2'
require 'erb'
require 'json'
Tilt.register Tilt::ERBTemplate, 'html.erb'

Mysql2::Client.default_query_options.merge!(:as => :array)
@@client = Mysql2::Client.new(:host => "192.168.91.2",:username => "testuser", :password => "mysqltest", :database => "bettingBase");


get '/' do
	erb :'home.html', :locals => {'client' => @@client}
end

get '/deathBet' do
	erb :'deathOptionPage.html'
end

post '/obtainDeathBetOptions' do
	require_relative 'views/testEndToEnd.rb'
	obtain_death_bet_options(@@client).to_json
end

get '/throneBet' do
	erb :'throneOptionPage.html'
end

post '/obtainThroneBetOptions' do
	require_relative 'views/testEndToEnd.rb'
	obtain_throne_bet_options(@@client).to_json
end

get '/resurrectBet' do
	erb :'resurrectOptionPage.html'
end

post '/obtainResurrectBetOptions' do
	require_relative 'views/testEndToEnd.rb'
	obtain_resurrect_bet_options(@@client).to_json
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
	bookNo = params[:bookNo]

	case betCategory
	when "throne"
		add_throne_bet(@@client, betCategory, betChoice, email, bet, bookNo)
	when "death"
		add_death_bet(@@client, betCategory, betChoice, email, bet, bookNo)
	when "resurrect"
		add_resurrect_bet(@@client, betCategory, betChoice, email, bet, bookNo)
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
	erb :'updatePerson.html', :locals => {'client' => @@client}
end

get '/updateHouse' do
	erb :'updateHouse.html', :locals => {'client' => @@client}
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

post '/updateCharacters' do
	require_relative 'views/testEndtoEnd.rb'
	data = JSON.parse(params[:arr])
	bookNo = params[:bookNo]
	data.each do |row|
		update_person(@@client, bookNo, row[0], row[1], row[2], row[3], row[4], row[5])
	end
	'/updateMenu'
end

post '/obtainHouses' do
	require_relative 'views/testEndtoEnd.rb'
	obtain_houses_and_data(@@client).to_json
end

post '/updateHouses' do
	require_relative 'views/testEndtoEnd.rb'
	data = JSON.parse(params[:arr])
	bookNo = params[:bookNo]
	data.each do |row|
		update_house(@@client, bookNo, row[0], row[1])
	end
	'/updateMenu'
end
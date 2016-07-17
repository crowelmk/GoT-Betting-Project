#!/usr/bin/ruby
require 'mysql2'

#connect to mysql database
def obtainCombatChart(client)
	result = client.query("SELECT HouseName, COUNT(*) AS Wins
                               FROM House AS h, CombatLog AS c
                               WHERE h.HouseID = c.HouseID AND c.Result = 'win'
                               GROUP BY h.HouseName")
	toReturn = [];
	names = [];
	wins = [];
	result.each do |val|
		names << val[0]
		wins << val[1]
	end
	toReturn << names
	toReturn << wins
	return toReturn
end

def add_house_bet(bet_option, client, email, bet_amount) 
	houseID = 0
	case bet_option
	when "lannister"
		houseID = 2
	when "stark"
		houseID = 9
	when "watch"
		houseID = 7
	when "greyjoy"
		houseID = 5
	when "baratheon"
		houseID = 6
	end


	statement = client.prepare("CALL insert_bet('house', ?, ?, ?, @out_value)")

	statement.execute(email, bet_amount, houseID)
end

def add_death_bet(bet_option, client, email, bet_amount) 
	charID = 0
	case bet_option
	when "aryastark"
		charID = 48
	when "jonsnow"
		charID = 381
	when "sansastark"
		charID = 688
	when "ramsaybolton"
		charID = 628
	when "theongreyjoy"
		charID = 742
	end

	statement = client.prepare("CALL insert_bet('death', ?, ?, ?, @out_value)")

	statement.execute(email, bet_amount, charID)
end

def add_resurrect_bet(bet_option, client, email, bet_amount) 
	charID = 0
	case bet_option
	when "nedstark"
		charID = 201
	when "joffreybaratheon"
		charID = 383
	when "khaldrogo"
		charID = 191
	when "viserystargaryen"
		charID = 797
	when "robbstark"
		charID = 651
	end

	statement = client.prepare("CALL insert_bet('resurrect', ?, ?, ?, @out_value)")

	statement.execute(email, bet_amount, charID)
end


# begin
#  # connect to the MySQL server
#  dbh = DBI.connect("DBI:Mysql:testBase:127.0.0.1", 
#                     "testuser", "mysqltest")
#  # get server version string and display it
#  row = dbh.select_one("SELECT VERSION()")
#  puts "Server version: " + row[0]
# rescue DBI::DatabaseError => e
#  puts "An error occurred"
#  puts "Error code:    #{e.err}"
#  puts "Error message: #{e.errstr}"
# ensure
#  # disconnect from server
#  dbh.disconnect if dbh
# end
# 
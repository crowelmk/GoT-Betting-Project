#!/usr/bin/ruby
require 'mysql2'

#connect to mysql database
def func(client)
	result = client.query("SELECT * FROM infoToGet")
	result.each do |val|
		return "#{val['id']}, #{val['name']}"
	end
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

	statement = client.prepare("INSERT INTO HouseBet(HouseID, UserEmail, CashBet)
						VALUES(?, ?, ?)")
	statement.execute(houseID, email, bet_amount)
end

def add_death_bet(bet_option, client, email, bet_amount) 
	charID = 0
	case bet_option
	when "Arya"
		charID = 48
	when "Jon"
		charID = 381
	when "Sansa"
		charID = 688
	when "Ramsay"
		charID = 628
	when "Theon"
		charID = 742
	end
	puts "#{charID}, #{bet_option}"
	statement = client.prepare("INSERT INTO MurderBet(CharID, UserEmail, CashBet)
						VALUES(?, ?, ?)")
	statement.execute(charID, email, bet_amount)
end

def add_resurrect_bet(bet_option, client, email, bet_amount) 
	charID = 0
	case bet_option
	when "Ned"
		charID = 201
	when "Joffrey"
		charID = 383
	when "Khal"
		charID = 191
	when "Viserys"
		charID = 797
	when "Robb"
		charID = 651
	end

	statement = client.prepare("INSERT INTO RFDBet(CharID, UserEmail, CashBet)
						VALUES(?, ?, ?)")
	statement.execute(charID, email, bet_amount)
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
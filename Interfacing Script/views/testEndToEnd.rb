#!/usr/bin/ruby
require 'mysql2'

def check_bet_availability(client, bet_type, book_num)
	numAvailable = 0
	result = client.query("SELECT COUNT(*)
							FROM BetOption
							WHERE Availability = 1 AND BetType = '#{bet_type}' 
							AND BookNo = #{book_num}")

	result.each do |val|
		numAvailable = val[0]
	end

	return numAvailable != 0
end

def grab_bet_winner(client, bet_type, book_num)
	winner = ""
	case bet_type
	when "death"
		winningOptionID = 0
		result = client.query("SELECT D.OptionID
								FROM DeathOption AS D, BetOption AS B, Event AS E
								WHERE D.OptionID = B.OptionID
									  AND D.CharID = E.ParticipantID
									  AND B.BetType = E.Description
									  AND B.BookNo = #{book_num}
									  AND E.ChangedBets = 1")

		result.each do |val|
			winningOptionID = val[0]
		end

		result2 = client.query("SELECT P.Name
									FROM DeathOption AS D, Person AS P
									WHERE D.OptionID = #{winningOptionID}
										  AND D.CharID = P.CharID")

		result2.each do |val|
			winner = val[0]
		end
	when "house"
		winningOptionID = 0
		result = client.query("SELECT H.OptionID
								FROM HouseOption AS H, BetOption AS B, Event AS E
								WHERE H.OptionID = B.OptionID
									  AND H.HouseID = E.ParticipantID 
									  AND B.BetType = E.Description
									  AND B.BookNo = #{book_num}
									  AND E.ChangedBets = 1")

		result.each do |val|
			winningOptionID = val[0]
		end

		result2 = client.query("SELECT S.HouseName
									FROM HouseOption AS H, House As S
									WHERE H.OptionID = #{winningOptionID}
										  AND H.HouseID = S.HouseID")

		result2.each do |val|
			winner = val[0]
		end
	when "resurrect"
		winningOptionID = 0
		result = client.query("SELECT R.OptionID
								FROM ResurrectOption AS R, BetOption AS B, Event AS E
								WHERE R.OptionID = B.OptionID
									  AND R.CharID = E.ParticipantID 
									  AND B.BetType = E.Description
									  AND B.BookNo = #{book_num}
									  AND E.ChangedBets = 1")

		result.each do |val|
			winningOptionID = val[0]
		end

		result2 = client.query("SELECT P.Name
									FROM ResurrectOption AS R, Person AS P
									WHERE R.OptionID = #{winningOptionID}
										  AND R.CharID = P.CharID")

		result2.each do |val|
			winner = val[0]
		end
	end

	return "#{winner}"
end

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
	optionID = 0
	nameToQuery = ""
	case bet_option
	when "lannister"
		nameToQuery = "Lannister"
	when "stark"
		nameToQuery = "Stark"
	when "watch"
		nameToQuery = "Night''s Watch"
	when "targaryen"
		nameToQuery = "Targaryen"
	when "baratheon"
		nameToQuery = "Baratheon"
	end

	result = client.query("SELECT OptionID
							FROM HouseOption AS H
							WHERE H.HouseID = (SELECT HouseID
												FROM House
												WHERE HouseName = '#{nameToQuery}')")

	result.each do |val|
		optionID = val[0]
		break
	end

	statement = client.prepare("INSERT INTO Bet(OptionID, UserEmail, BetAmount)
								VALUES(?, ?, ?)")

	statement.execute(optionID, email, bet_amount)
end

def add_death_bet(bet_option, client, email, bet_amount) 
	optionID = 0
	nameToQuery = ""
	case bet_option
	when "aryastark"
		nameToQuery = "Arya Stark"
	when "jonsnow"
		nameToQuery = "Jon Snow"
	when "sansastark"
		nameToQuery = "Sansa Stark"
	when "ramsaysnow"
		nameToQuery = "Ramsay Snow"
	when "theongreyjoy"
		nameToQuery = "Theon Greyjoy"
	end

	result = client.query("SELECT OptionID
							FROM DeathOption AS D
							WHERE D.CharID = ( SELECT CharID
												FROM Person
												WHERE Name = '#{nameToQuery}')")

	result.each do |val|
		optionID = val[0]
		break
	end

	statement = client.prepare("INSERT INTO Bet(OptionID, UserEmail, BetAmount)
								VALUES(?, ?, ?)")

	statement.execute(optionID, email, bet_amount)
end

def add_resurrect_bet(bet_option, client, email, bet_amount) 
	charID = 0
	nameToQuery = ""
	case bet_option
	when "nedstark"
		nameToQuery = "Eddard Stark"
	when "joffreybaratheon"
		nameToQuery = "Joffrey Baratheon"
	when "khaldrogo"
		nameToQuery = "Drogo"
	when "viserystargaryen"
		nameToQuery = "Viserys Targaryen"
	when "robbstark"
		nameToQuery = "Robb Stark"
	end

	result = client.query("SELECT OptionID
							FROM ResurrectOption AS R
							WHERE R.CharID = ( SELECT CharID
												FROM Person
												WHERE Name = '#{nameToQuery}')")

	result.each do |val|
		optionID = val[0]
		break
	end


	statement = client.prepare("INSERT INTO Bet(OptionID, UserEmail, BetAmount)
								VALUES(?, ?, ?)")

	statement.execute(optionID, email, bet_amount)
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
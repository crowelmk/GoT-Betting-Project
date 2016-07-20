#!/usr/bin/ruby
require 'mysql2'

def obtain_bet_history(client, bet_type, email)
	result = nil
	toReturn = []

	email.gsub("@", "\@")
	case bet_type
	when "Death"
		result = client.query("(SELECT B.UserEmail, E.EventType, E.ParticipantName, B.Status, B.BetAmount
									FROM Bet AS B, Event AS E, DeathOption AS D
									WHERE B.OptionID = D.OptionID 
										  AND B.ResolvingEventID = E.EventID
										  AND B.UserEmail = '%s')
								UNION
								(SELECT B.UserEmail, P.BetType, 'NONE' AS Name, B.Status, B.BetAmount
									FROM Bet AS B, BetOption AS P, DeathOption AS D
									WHERE B.OptionID = D.OptionID
										  AND B.ResolvingEventID IS NULL
										  AND B.UserEmail = '%s')" % [email, email])
	when "Throne"
		result = client.query("(SELECT B.UserEmail, E.EventType, E.ParticipantName, B.Status, B.BetAmount
								FROM Bet AS B, Event AS E, ThroneOption AS T
									WHERE B.OptionID = T.OptionID
										  AND (B.ResolvingEventID = E.EventID)
										  AND B.UserEmail = '%s')
								UNION
								(SELECT B.UserEmail, P.BetType, 'NONE' AS Name, B.Status, B.BetAmount
									FROM Bet AS B, BetOption AS P, ThroneOption AS T
									WHERE B.OptionID = T.OptionID 
										  AND B.ResolvingEventID IS NULL
										  AND B.UserEmail = '%s')" % [email, email])
	when "Resurrect"
		result = client.query("(SELECT B.UserEmail, E.EventType, E.ParticipantName, B.Status, B.BetAmount
									FROM Bet AS B, Event AS E, ResurrectOption AS R
									WHERE B.OptionID = R.OptionID 
										  AND (B.ResolvingEventID = E.EventID)
										  AND B.UserEmail = '%s')
								UNION
								(SELECT B.UserEmail, P.BetType, 'NONE' AS Name, B.Status, B.BetAmount
									FROM Bet AS B, BetOption AS P, ResurrectOption AS R
									WHERE B.OptionID = R.OptionID,
										  AND B.ResolvingEventID IS NULL
										  AND B.UserEmail = '%s')" % [email, email])
	when "All"
		result = client.query("(SELECT B.UserEmail, E.EventType, E.ParticipantName, B.Status, B.BetAmount
									FROM Bet AS B, Event AS E
									WHERE B.ResolvingEventID = E.EventID
										  AND B.UserEmail = '%s')
								UNION
								(SELECT B.UserEmail, P.BetType, 'NONE' AS Name, B.Status, B.BetAmount
									FROM Bet AS B, BetOption AS P
									WHERE B.OptionID = P.OptionID
										  AND B.ResolvingEventID IS NULL
										  AND B.UserEmail = '%s')" % [email, email])
	end

	result.each do |val|
		# Convert big decimals to displayable floats
		val[4] = val[4].to_s("F")
		toReturn << val
	end

	return toReturn
end

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
									  AND B.BetType = E.EventType
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
	when "throne"
		winningOptionID = 0
		result = client.query("SELECT T.OptionID
								FROM ThroneOption AS T, BetOption AS B, Event AS E
								WHERE T.OptionID = B.OptionID
									  AND T.HouseID = E.ParticipantID 
									  AND B.BetType = E.EventType
									  AND B.BookNo = #{book_num}
									  AND E.ChangedBets = 1")

		result.each do |val|
			winningOptionID = val[0]
		end

		result2 = client.query("SELECT S.HouseName
									FROM ThroneOption AS T, House As H
									WHERE T.OptionID = #{winningOptionID}
										  AND T.HouseID = H.HouseID")

		result2.each do |val|
			winner = val[0]
		end
	when "resurrect"
		winningOptionID = 0
		result = client.query("SELECT R.OptionID
								FROM ResurrectOption AS R, BetOption AS B, Event AS E
								WHERE R.OptionID = B.OptionID
									  AND R.CharID = E.ParticipantID 
									  AND B.BetType = E.EventType
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

def add_throne_bet(bet_option, client, email, bet_amount) 
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
							FROM Throneption AS T
							WHERE T.HouseID = (SELECT HouseID
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
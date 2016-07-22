#!/usr/bin/ruby
require 'mysql2'

def get_odds(client, bet_type, bookNo, name)
	odds = 0
	case bet_type
	when "death"
		result = client.query("SELECT B.Odds
									FROM Person AS P, BetOption AS B, DeathOption AS D
									WHERE P.CharID = D.CharID
										  AND B.OptionID = D.OptionID
										  AND P.Name = '%s'
										  AND B.BookNo = %d" % [name, bookNo])

		result.each do |val|
			odds = val[0]
		end
	when "throne"
		result = client.query("SELECT B.Odds
								FROM House AS H, BetOption AS B, ThroneOption AS T
								WHERE H.HouseID = T.HouseID
									  AND B.OptionID = T.OptionID
									  AND H.HouseName = '%s'
									  AND B.BookNo = %d" % [name, bookNo])

		result.each do |val|
			odds = val[0]
		end
	when "resurrect"
		result = client.query("SELECT B.Odds
									FROM Person AS P, BetOption AS B, ResurrectOption AS R
									WHERE P.CharID = R.CharID
										  AND B.OptionID = R.OptionID
										  AND P.Name = '%s'
										  AND B.BookNo = %d" % [name, bookNo])

		result.each do |val|
			odds = val[0]
		end
	end

	return odds.to_f
end

def obtain_bet_history(client, bet_type, email)
	result = nil
	toReturn = []

	email.gsub("@", "\@")
	case bet_type
	when "Death"
		result = client.query("(SELECT B.UserEmail, E.EventType, E.ParticipantName, 
									   B.Status, B.BetAmount, P.Odds
									FROM Bet AS B, Event AS E, BetOption AS P
									WHERE B.OptionID = P.OptionID 
										  AND P.BetType = 'death'
										  AND B.ResolvingEventID = E.EventID
										  AND B.UserEmail = '%s')
								UNION
								(SELECT B.UserEmail, P.BetType, 'NONE' AS Name,
										B.Status, B.BetAmount, P.Odds
									FROM Bet AS B, BetOption AS P
									WHERE B.OptionID = P.OptionID 
										  AND P.BetType = 'death'
										  AND B.ResolvingEventID IS NULL
										  AND B.UserEmail = '%s')" % [email, email])
	when "Throne"
		result = client.query("(SELECT B.UserEmail, E.EventType, E.ParticipantName, 
									   B.Status, B.BetAmount, P.Odds
								FROM Bet AS B, Event AS E, BetOption AS P
									WHERE B.OptionID = P.OptionID
										  AND P.BetType = 'throne'
										  AND (B.ResolvingEventID = E.EventID)
										  AND B.UserEmail = '%s')
								UNION
								(SELECT B.UserEmail, P.BetType, 'NONE' AS Name,
									    B.Status, B.BetAmount, P.Odds
									FROM Bet AS B, BetOption AS P
									WHERE B.OptionID = P.OptionID
										  AND P.BetType = 'throne' 
										  AND B.ResolvingEventID IS NULL
										  AND B.UserEmail = '%s')" % [email, email])
	when "Resurrect"
		result = client.query("(SELECT B.UserEmail, E.EventType, E.ParticipantName, 
									   B.Status, B.BetAmount, P.Odds
									FROM Bet AS B, Event AS E, BetOption AS P
									WHERE B.OptionID = P.OptionID
										  AND P.BetType = 'resurrect'
										  AND B.ResolvingEventID = E.EventID
										  AND B.UserEmail = '%s')
								UNION
								(SELECT B.UserEmail, P.BetType, 'NONE' AS Name, 
										B.Status, B.BetAmount, P.Odds
									FROM Bet AS B, BetOption AS P
									WHERE B.OptionID = P.OptionID
										  AND P.BetType = 'resurrect'
										  AND B.ResolvingEventID IS NULL
										  AND B.UserEmail = '%s')" % [email, email])
	when "All"
		result = client.query("(SELECT B.UserEmail, E.EventType, E.ParticipantName,
									   B.Status, B.BetAmount, P.Odds
									FROM Bet AS B, Event AS E, BetOption AS P
									WHERE B.ResolvingEventID = E.EventID
										  AND B.OptionID = P.OptionID
										  AND B.UserEmail = '%s')
								UNION
								(SELECT B.UserEmail, P.BetType, 'NONE' AS Name, B.Status, 
										B.BetAmount, P.Odds
									FROM Bet AS B, BetOption AS P
									WHERE B.OptionID = P.OptionID
										  AND B.ResolvingEventID IS NULL
										  AND B.UserEmail = '%s')" % [email, email])
	end

	result.each do |val|
		# Convert big decimals to displayable floats
		val[4] = val[4].to_s("F")
		# Put whole row into array
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

		result2 = client.query("SELECT H.HouseName
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

def obtainWinsData(client)
	result = client.query("SELECT HouseName, NumBattlesWon
                               FROM HouseBattleWinStats")
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

def obtainMembershipData(client)
	result = client.query("SELECT HouseName, NumTotalMembers
                               FROM HouseMembership")
	toReturn = [];
	names = [];
	members = [];
	result.each do |val|
		names << val[0]
		members << val[1]
	end
	toReturn << names
	toReturn << members
	return toReturn
end

def obtainDeathData(client)
	result = client.query("SELECT HouseName, NumMembersDead
                               FROM HouseDeathStats")
	toReturn = [];
	names = [];
	deaths = [];
	result.each do |val|
		names << val[0]
		deaths << val[1]
	end
	toReturn << names
	toReturn << deaths
	return toReturn
end

def obtainPopularityData(client)
	result = client.query("SELECT Name, Popularity
                               FROM Person
                               ORDER BY Popularity DESC")
	toReturn = []
	names = []
	popularity = []

	numEntries = 0
	result.each do |val|
		names << val[0]
		popularity << (val[1].to_f * 100).round

		numEntries = numEntries + 1

		if numEntries > 40
			break;
		end
	end

	toReturn << names
	toReturn << popularity
	return toReturn
end

def obtainDeathProbData(client)
	result = client.query("SELECT Name, DeathProbability
                               FROM Person
                               ORDER BY DeathProbability DESC")
	toReturn = []
	names = []
	deathProb = []

	numEntries = 0
	result.each do |val|
		names << val[0]
		deathProb << (val[1].to_f * 100).round

		numEntries = numEntries + 1

		if numEntries > 40
			break;
		end
	end
	
	toReturn << names
	toReturn << deathProb

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
	when "tully"
		nameToQuery = "Tully"
	when "baratheon"
		nameToQuery = "Baratheon"
	end

	result = client.query("SELECT OptionID
							FROM ThroneOption AS T
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
	when "daenerystargaryen"
		nameToQuery = "Daenerys Targaryen"
	when "jaimelannister"
		nameToQuery = "Jaime Lannister"
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
	optionID = 0
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

def update_person(client, char_name, bookNo, house_name, title, 
	isAlive, deathProb, popularity)
	puts "#{isAlive}, #{bookNo}"
	if isAlive == ""
		isAlive = 2
	end

	if deathProb == ""
		deathProb = -1
	end

	if popularity == ""
		popularity = -1
	end


	client.query("CALL update_person('%s', '%s', '%s', %d, %.3f, %.6f, %d, @output_value)" % [char_name, house_name, title, isAlive, deathProb, popularity, bookNo])
end

def update_house(client, house_name, bookNo, wonThrone)
	if wonThrone == ""
		wonThrone = 2
	end


	client.query("CALL update_house('%s', %d, %d, @output_value)" % [house_name, wonThrone, bookNo])
end

def delete_event(client, name, bookNo, event_type)
	eventID = 0
	result = client.query("SELECT MAX(EventID)
							FROM Event
							WHERE ParticipantName = '%s'
								  AND BookOccurred = %d
								  AND EventType = '%s'" % [name, bookNo, event_type])

	result.each do |val|
		eventID = val[0]
	end

	if eventID != nil
		client.query("CALL delete_event(#{eventID}, @output_value)")
		puts "Deletion was successful!"
	else
		puts "No matching event found, deletion failed."
	end
end
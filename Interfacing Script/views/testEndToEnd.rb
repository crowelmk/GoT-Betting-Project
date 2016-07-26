#!/usr/bin/ruby
require 'mysql2'

def remove_bad_char(inputString)
	if(inputString != nil)
		return inputString.gsub("'", "''")
	end
end

def obtain_bet_history(client, bet_type, email)
	result = nil
	toReturn = []

	email.gsub("@", "\@")
	case bet_type
	when "Death"
		result = client.query("SELECT B.UserEmail, B.BetType, B.OptionName, 
							  B.BookNo, B.BetAmount, E.Description, P.Odds
								FROM Bet AS B LEFT JOIN Event AS E 
									 ON B.OptionName = E.ParticipantName
										AND B.BookNo = E.BookOccurred,
									 Person AS P
								WHERE B.OptionID = P.CharID
									  AND B.BetType = 'death'
									  AND B.UserEmail = '%s'" % email)
	when "Throne"
		result = client.query("SELECT B.UserEmail, B.BetType, B.OptionName, 
							  B.BookNo, B.BetAmount, E.Description, H.Odds
								FROM Bet AS B LEFT JOIN Event AS E 
									 ON B.OptionName = E.ParticipantName
										AND B.BookNo = E.BookOccurred,
									 House AS H
								WHERE B.OptionID = H.HouseID
									  AND B.BetType = 'throne'
									  AND B.UserEmail = '%s'" % email)
	when "Resurrect"
		result = client.query("SELECT B.UserEmail, B.BetType, B.OptionName, 
							  B.BookNo, B.BetAmount, E.Description, P.Odds
								FROM Bet AS B LEFT JOIN Event AS E 
									 ON B.OptionName = E.ParticipantName
										AND B.BookNo = E.BookOccurred,
									 Person AS P
								WHERE B.OptionID = P.CharID
									  AND B.BetType = 'resurrect'
									  AND B.UserEmail = '%s'" % email)
	when "All"
		result = client.query("(SELECT B.UserEmail, B.BetType, B.OptionName, 
								  B.BookNo, B.BetAmount, E.Description, P.Odds
									FROM Bet AS B LEFT JOIN Event AS E 
										 ON B.OptionName = E.ParticipantName
											AND B.BookNo = E.BookOccurred,
										 Person AS P
									WHERE B.OptionID = P.CharID
										  AND B.UserEmail = '%s')
								UNION
								(SELECT B.UserEmail, B.BetType, B.OptionName, 
									  B.BookNo, B.BetAmount, E.Description, H.Odds
										FROM Bet AS B LEFT JOIN Event AS E 
											 ON B.OptionName = E.ParticipantName
											 AND B.BookNo = E.BookOccurred,
											 House AS H
										WHERE B.OptionID = H.HouseID
											  AND B.UserEmail = '%s')" % [email, email])
	end

	result.each do |val|
		# Convert big decimals to displayable floats
		val[4] = val[4].to_f
		val[6] = val[6].to_f
		# Put whole row into array
		toReturn << val
	end

	return toReturn
end

def obtain_death_bet_options(client) 
	result = client.query("SELECT Name, Odds
                               FROM Person
                               WHERE IsOption = 1 
                               		 AND IsAlive = 1")
	
	toReturn = [] 

	result.each do |val|
		val[1] = val[1].to_f
		toReturn << val
	end

	return toReturn
end

def obtain_throne_bet_options(client) 
	result = client.query("SELECT HouseName, Odds
                               FROM House
                               WHERE IsOption = 1 ")
	
	toReturn = [] 

	result.each do |val|
		val[1] = val[1].to_f
		toReturn << val
	end

	return toReturn
end

def obtain_resurrect_bet_options(client) 
	result = client.query("SELECT Name, Odds
                               FROM Person
                               WHERE IsOption = 1 
                               		 AND IsAlive = 0")
	
	toReturn = [] 

	result.each do |val|
		val[1] = val[1].to_f
		toReturn << val
	end

	return toReturn
end

def add_death_bet(client, bet_type, bet_option, email, bet_amount, bookNo) 
	optionID = 0
	result = client.query("SELECT CharID
							FROM Person
							WHERE Name = '%s'" % bet_option)

	result.each do |val|
		optionID = val[0]
		break
	end

	if optionID == 0
		puts "No matching character to bet on was found."
		return
	end

	client.query("INSERT INTO Bet(OptionID, OptionName, BetType, BookNo, UserEmail, BetAmount)
					VALUES(%d, '%s','%s', %d, '%s', %.2f)" % [optionID, bet_option, bet_type, bookNo, email, bet_amount])
end

def add_throne_bet(client, bet_type, bet_option, email, bet_amount, bookNo) 
	optionID = 0
	result = client.query("SELECT HouseID
							FROM House
							WHERE HouseName = '%s'" % bet_option)

	result.each do |val|
		optionID = val[0]
		break
	end

	if optionID == 0
		puts "No matching house to bet on was found."
		return
	end

	client.query("INSERT INTO Bet(OptionID, OptionName, BetType, BookNo, UserEmail, BetAmount)
					VALUES(%d, '%s','%s', %d, '%s', %.2f)" % [optionID, bet_option, bet_type, bookNo, email, bet_amount])
end

def add_resurrect_bet(client, bet_type, bet_option, email, bet_amount, bookNo) 
	optionID = 0
	result = client.query("SELECT CharID
							FROM Person
							WHERE Name = '%s'" % bet_option)

	result.each do |val|
		optionID = val[0]
		break
	end

	if optionID == 0
		puts "No matching character to bet on was found."
		return
	end

	client.query("INSERT INTO Bet(OptionID, OptionName, BetType, BookNo, UserEmail, BetAmount)
					VALUES(%d, '%s','%s', %d, '%s', %.2f)" % [optionID, bet_option, bet_type, bookNo, email, bet_amount])
end

def obtain_some_characters_some_data(client)
	result = client.query("SELECT Name, IsAlive
								FROM Person
								WHERE IsOption = 1
								ORDER BY IsAlive DESC,
										 Name")

	toReturn = []
	result.each do |val|
		toReturn << val
	end

	return toReturn
end

def obtain_some_characters_all_data(client)
	result = client.query("(SELECT Name, IsAlive, H.HouseName, 
								   Title, Popularity, DeathProbability
							FROM Person AS P, House AS H
							WHERE P.HouseID = H.HouseID
								  AND P.IsOption = 1
							ORDER BY IsAlive DESC,
									 Name)
							UNION
							(SELECT Name, IsAlive, 'Unaffiliated' AS HName, 
									Title, Popularity, DeathProbability
							FROM Person AS P, House AS H
							WHERE P.HouseID IS NULL
								  AND P.IsOption = 1
							ORDER BY IsAlive DESC,
									 Name)")

	toReturn = []
	result.each do |val|
		val[4] = val[4].to_f
		val[5] = val[5].to_f
		toReturn << val
	end

	return toReturn
end

def obtain_all_characters_some_data(client)
	result = client.query("SELECT Name, IsAlive
								FROM Person
								ORDER BY IsOption DESC,
										 IsAlive DESC,
										 Name")

	toReturn = []
	result.each do |val|
		toReturn << val
	end

	return toReturn
end

def update_person(client, bookNo, char_name, isAlive, 
	house_name, title, popularity, deathProb)

	char_name = remove_bad_char(char_name)
	house_name = remove_bad_char(house_name)
	title = remove_bad_char(title)
	client.query("CALL log_and_update_person('%s', '%s', '%s', %d, %.3f, %.6f, %d, @output_value)" % [char_name, house_name, title, isAlive, deathProb, popularity, bookNo])
end

def obtain_all_characters_all_data(client)
	result = client.query("(SELECT Name, IsAlive, H.HouseName, 
								   Title, Popularity, DeathProbability
							FROM Person AS P, House AS H
							WHERE P.HouseID = H.HouseID
							ORDER BY P.IsOption DESC,
									 IsAlive DESC,
									 Name)
							UNION
							(SELECT Name, IsAlive, 'Unaffiliated' AS HName, 
									Title, Popularity, DeathProbability
							FROM Person AS P, House AS H
							WHERE P.HouseID IS NULL
							ORDER BY P.IsOption DESC,
									 IsAlive DESC,
									 Name)")

	toReturn = []
	result.each do |val|
		val[4] = val[4].to_f
		val[5] = val[5].to_f
		toReturn << val
	end

	return toReturn
end

def obtain_houses_and_data(client)
	result = client.query("SELECT HouseName, WonThrone, IsOption
							FROM House")


	toReturn = []
	result.each do |val|
		toReturn << val
	end

	return toReturn
end

def update_house(client, bookNo, house_name, wonThrone)

	house_name = remove_bad_char(house_name)
	client.query("CALL log_and_update_house('%s', %d, %d, @output_value)" % [house_name, wonThrone, bookNo])
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

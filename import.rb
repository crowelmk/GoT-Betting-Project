require 'csv'
require 'Mysql2'
require 'set'
require 'optparse'


mode = nil
OptionParser.new do |opts|
  opts.on("-m MODE", "--mode MODE", "MODE of import to perform") do |val|
    mode = val;
  end
end.parse(ARGV)
raise "You must specify whether to 'create' database or 'add' to database (-m)" if mode.nil?


def remove_bad_char(inputString)
	if(inputString != nil)
		return inputString.gsub("'", "''")
	end
end

def create_database(client, dbName)
	client.query("DROP DATABASE IF EXISTS #{dbName}")
	client.query("CREATE DATABASE #{dbName}")
end

def drop_tables(client)
	# client.query("DROP TABLE IF EXISTS DeathBet")
	# client.query("DROP TABLE IF EXISTS RFDBet")
	# client.query("DROP TABLE IF EXISTS HouseBet")
	client.query("DROP TABLE IF EXISTS Bet")
	client.query("DROP TABLE IF EXISTS CombatLog")
	client.query("DROP TABLE IF EXISTS Person")
	client.query("DROP TABLE IF EXISTS House")
	client.query("DROP TABLE IF EXISTS Battle")
	client.query("DROP TABLE IF EXISTS Event")
	client.query("DROP TABLE IF EXISTS HouseOption")
	client.query("DROP TABLE IF EXISTS DeathOption")
	client.query("DROP TABLE IF EXISTS ResurrectOption")
	client.query("DROP TABLE IF EXISTS BetOption")

end

def create_tables_and_views(client)
	# Tables

	# Note: House has multiple derived attributes that are expressed in a view on House involving both
	# the combat log and the Person and Death tables.
	client.query("CREATE TABLE IF NOT EXISTS House (
					HouseID INT PRIMARY KEY,
					HouseName VARCHAR(80) NOT NULL UNIQUE,
					WonThrone SMALLINT NOT NULL,
					CHECK(WonThrone = 0 OR WonThrone = 1))")

	client.query("CREATE TABLE IF NOT EXISTS Person (
					CharID INT PRIMARY KEY, 
					IsAlive SMALLINT NOT NULL,
					HouseID INT NOT NULL, 
					Name varchar(80) NOT NULL, 
					Gender INT NOT NULL, 
					Title varchar(60), 
					IntroBookNo INT, 
					FOREIGN KEY(HouseID) REFERENCES House(HouseID))")

	# client.query("CREATE TABLE IF NOT EXISTS Death (
	# 				DeathID INT, 
	# 				CharID INT, 
	# 				DeathYear INT NOT NULL, 
	# 				DeathBookNo INT, 
	# 				DeathChapterNo INT, 
	# 				PRIMARY KEY(DeathID, CharID), 
	# 				FOREIGN KEY(CharID) REFERENCES Person(CharID),
	# 				CHECK(DeathYear > 296))")

	client.query("CREATE TABLE IF NOT EXISTS Battle (
					BattleID INT PRIMARY KEY, 
					BattleName VARCHAR(80) NOT NULL, 
					City VARCHAR(60), 
					Year INT)")

	client.query("CREATE TABLE IF NOT EXISTS CombatLog (
					HouseID INT NOT NULL, 
					BattleID INT NOT NULL, 
					Result VARCHAR(60), 
					PRIMARY KEY(HouseID, BattleID),
					FOREIGN KEY(HouseID) REFERENCES House(HouseID), 
					FOREIGN KEY(BattleID) REFERENCES Battle(BattleID))")

	client.query("CREATE TABLE IF NOT EXISTS Event (
					EventID INT AUTO_INCREMENT PRIMARY KEY, 
					ParticipantID INT NOT NULL,
					Description VARCHAR(80) NOT NULL,
					BookOccurred SMALLINT NOT NULL,
					ChangedBets SMALLINT NOT NULL
					CHECK(ChangedBets = 0 OR ChangedBets = 1))")

	client.query("CREATE TABLE IF NOT EXISTS BetOption (
					OptionID INT AUTO_INCREMENT PRIMARY KEY, 
					BetType VARCHAR(80) NOT NULL,
					BookNo SMALLINT NOT NULL,
					Availability SMALLINT NOT NULL,
					CHECK(Availability = 0 OR Availability = 1))")

	client.query("CREATE TABLE IF NOT EXISTS DeathOption(
					OptionID INT NOT NULL PRIMARY KEY,
					CharID INT NOT NULL,
					FOREIGN KEY(OptionID) REFERENCES BetOption(OptionID),
					FOREIGN KEY(CharID) REFERENCES Person(CharID))")

	client.query("CREATE TABLE IF NOT EXISTS HouseOption(
					OptionID INT NOT NULL PRIMARY KEY,
					HouseID INT NOT NULL,
					FOREIGN KEY(OptionID) REFERENCES BetOption(OptionID),
					FOREIGN KEY(HouseID) REFERENCES House(HouseID))")

	client.query("CREATE TABLE IF NOT EXISTS ResurrectOption(
					OptionID INT NOT NULL PRIMARY KEY,
					CharID INT NOT NULL,
					FOREIGN KEY(OptionID) REFERENCES BetOption(OptionID),
					FOREIGN KEY(CharID) REFERENCES Person(CharID))")

	client.query("CREATE TABLE IF NOT EXISTS Bet (
					BetID INT AUTO_INCREMENT PRIMARY KEY,
					OptionID INT NOT NULL,
					UserEmail VARCHAR(100) NOT NULL,
					BetAmount DECIMAL(10, 2) NOT NULL,
					FOREIGN KEY(OptionID) REFERENCES BetOption(OptionID),
					CHECK(CashBet > 1.00))")

	# client.query("CREATE TABLE IF NOT EXISTS DeathBet (
	# 				BetID INT NOT NULL, 
	# 				CharID INT NOT NULL, 
	# 				FOREIGN KEY(BetID) REFERENCES Bet(BetID),
	# 				FOREIGN KEY(CharID) REFERENCES Person(CharID),
	# 				PRIMARY KEY(BetID))")

	# # RFD = Resurrect from death
	# client.query("CREATE TABLE IF NOT EXISTS RFDBet (
	# 				BetID INT NOT NULL, 
	# 				CharID INT NOT NULL, 
	# 				FOREIGN KEY(BetID) REFERENCES Bet(BetID),
	# 				FOREIGN KEY(CharID) REFERENCES Death(CharID),
	# 				PRIMARY KEY(BetID))")

	# client.query("CREATE TABLE IF NOT EXISTS HouseBet (
	# 				BetID INT NOT NULL, 
	# 				HouseID INT NOT NULL, 
	# 				FOREIGN KEY(BetID) REFERENCES Bet(BetID),
	# 				FOREIGN KEY(HouseID) REFERENCES House(HouseID),
	# 				PRIMARY KEY(BetID))")

	# Views
	client.query("CREATE OR REPLACE VIEW HouseMembership (
					HouseID, HouseName, NumTotalMembers)
					AS SELECT H.HouseID, H.HouseName, COUNT(P.CharID)
								FROM House AS H, Person P
								WHERE H.HouseID = P.HouseID
								GROUP BY HouseID")

	client.query("CREATE OR REPLACE VIEW HouseDeathStats (
					HouseID, HouseName, NumMembersDead)
					AS SELECT H.HouseID, H.HouseName, COUNT(P.CharID)
							FROM House AS H, Person AS P
							WHERE H.HouseID = P.HouseID AND P.IsAlive = 0
							GROUP BY HouseID")

	client.query("CREATE OR REPLACE VIEW HouseBattleStats (
					HouseID, HouseName, NumBattlesWon)
					AS SELECT H.HouseID, H.HouseName, COUNT(BattleID)
							FROM House AS H, CombatLog L
							WHERE H.HouseID = L.HouseID AND result = 'win'
							GROUP BY HouseID")
end

def populate_option_tables(client)
	deathQuery = client.query("SELECT CharID
								FROM Person
								WHERE Name IN ('Arya Stark', 'Jon Snow', 'Sansa Stark', 
								'Ramsay Snow', 'Theon Greyjoy')")

	deathIDs = []
	deathQuery.each do |val|
		deathIDs << val[0]
	end

	deathIDs.each do |id|
		client.query("CALL insert_bet_option('death', #{id}, 6, @output_value)")
	end


	resurrectQuery = client.query("SELECT CharID
									FROM Person
									WHERE Name IN ('Eddard Stark', 'Joffrey Baratheon', 
									'Drogo', 'Viserys Targaryen', 'Robb Stark')")
	
	resurrectIDs = []
	resurrectQuery.each do |val|
		resurrectIDs << val[0]
	end

	resurrectIDs.each do |id|
		client.query("CALL insert_bet_option('resurrect', #{id}, 6, @output_value)")
	end


	houseQuery = client.query("SELECT HouseID
									FROM House
									WHERE HouseName IN ('Lannister', 'Stark', 
									'Night''s Watch', 'Targaryen', 'Baratheon')")
	houseIDs = []
	houseQuery.each do |val|
		houseIDs << val[0]
	end

	houseIDs.each do |id|
		client.query("CALL insert_bet_option('house', #{id}, 6, @output_value)")
	end
end

def populate_tables(client, people, stats, battles) 
	# Create a list of names from the prediction csv file. We only want to add names that appear both in
	# this "prediction" file and those that appear in the "character" file. Using a mapping allows us
	# to quickly check the keys for matches, which will then be inserted into the Person table.
	personNamesHash = Hash.new()
	lastIndex = stats.size-1
	for i in 1..lastIndex
		personNamesHash.merge!({stats[i][5] => i})
	end

	# Set to store names of houses obtained from parsing the table of people
	houseNames = Set.new()

	# Grab house names from a column in table of people. 
	# This is needed for populating the house table.
	people.each do |person|
		# Add the current character's house to the set of houses. If this house (or one
        # with a matching name) has already been added, then this operation will not 
        # do anything.
		houseName = person[1]

		# Given our source's formatting, there may be two names such as "Stark" and
		# "House Stark." To avoid this issue, we will each name by " " and, if the
		# first part is "House", remove the first part.
		houseNameSplit = houseName.split(" ")
		if houseNameSplit[0] == "House"
			houseName = houseNameSplit[1]
		end
		houseNames.add(houseName)
	end

	# Relate house names (keys) to HouseIDs (values). This allows us to
	# populate the foreign keys for house membership in Person with actual
	# matching HouseIDs from the House table.
	houseIdMapping = Hash.new();

	# Populate the house table.
	houseNamesArray = houseNames.to_a
	lastIndex = houseNamesArray.length - 1
	for i in 1..lastIndex
		houseId = i + 1

		currentName = houseNamesArray[i]
		if currentName == nil
			currentName = "Unaffiliated"
		end

		houseIdMapping.merge!({currentName => houseId})

		currentName = remove_bad_char(currentName)

		client.query("INSERT INTO House(HouseID, HouseName, WonThrone)
			          VALUE(#{houseId}, '#{currentName}', 0)")
	end


	# Insert values into character and death tables
	currentIdValue = 1
	people.each do |person|
		name = person[0]
		if personNamesHash.has_key?(name)
			statRow = personNamesHash.fetch(name)
			name = remove_bad_char(name)

			gender = stats[statRow][7].to_i

			title = stats[statRow][6]
			title = remove_bad_char(title)

			bookIndex = 8
			while(person[bookIndex].to_i == 0) 
				bookIndex = bookIndex + 1
			end
			introBookNo = bookIndex - 7

			houseName = person[1]
			if houseName == nil 
				houseName = "Unaffiliated"
			end
			houseNameSplit = person[1].split(" ")
			if houseNameSplit[0] == "House"
				houseName = houseNameSplit[1]
			end

			personIsAlive = person[2] != nil ? 0 : 1

			houseId = houseIdMapping.fetch(houseName)
	        client.query("INSERT INTO Person(CharID, IsAlive, HouseID, Name, Gender, Title, IntroBookNo) 
	        VALUES(#{currentIdValue}, #{personIsAlive}, #{houseId}, '#{name}', #{gender}, '#{title}', #{introBookNo})")

			# if(person[2] != nil) # person is dead, record their death
			# 	# In our imported data, no person has died twice. However, since characters
			# 	# are able to be resurrected, it is worth having a deathId that tracks which
			# 	# death a character's entry in the DEATH table refers to.
			# 	deathId = 1

			# 	deathYear = person[2].to_i

			# 	deathBookNo = person[3].to_i

			# 	deathBookChap = person[4].to_i

			# 	client.query("INSERT INTO Death(DeathID, CharID, DeathYear, DeathBookNo, DeathChapterNo)
	  #      	 				  VALUES(#{deathId}, #{currentIdValue}, #{deathYear}, #{deathBookNo}, #{deathBookChap})")
			# end
			currentIdValue = currentIdValue + 1
		end
	end

	# Insert values into Battle table
	currentIdValue = 1
	battles.each do |battle|
		battleName = battle[0]
		battleName = remove_bad_char(battleName)

		location = battle[22]
		location = remove_bad_char(location)

		year = battle[1].to_i

		client.query("INSERT INTO Battle (BattleID, BattleName, City, Year)
			          VALUE(#{currentIdValue}, '#{battleName}' ,'#{location}',#{year})")

		currentIdValue = currentIdValue + 1
	end

	# Insert values into CombatLog table (M:N relationship Houses : Battles)
	currentBattleId = 1
	battles.each do |battle|
		# Compile a list of all attackers from battle document
		firstAttackIndex = 5
		lastAttackIndex = 8
		attackers = []
		for j in firstAttackIndex..lastAttackIndex
			if (battle[j] != nil)
				attackers << battle[j]
			end
		end

		# Compile a list of all defenders from battle document
		firstDefendIndex = 9
		lastDefendIndex = 12
		defenders = []
		for j in firstDefendIndex..lastDefendIndex
			if (battle[j] != nil)
				defenders << battle[j]
			end
		end

		# Obtain the necessary data to insert each attacker into the CombatLog table.
		attackers.each do |name|
			if(houseIdMapping.has_key?(name) && !defenders.include?(name)) 
				houseId = houseIdMapping.fetch(name)

				result = ""
				if (battle[13] == "win")
					result = "win"
				elsif (battle[13] == "loss")
					result = "loss"
				else
					result = "inconclusive"
				end
				client.query("INSERT INTO CombatLog()
	        	VALUES(#{houseId}, #{currentBattleId}, '#{result}')")
			end
		end

		# Obtain the necessary data to insert each defender into the CombatLog table.
		defenders.each do |name|
			if(houseIdMapping.has_key?(name)&& !attackers.include?(name))
				houseId = houseIdMapping.fetch(name)

				result = ""
				if (battle[13] == "win")
					result = "loss"
				elsif (battle[13] == "loss")
					result = "win"
				else
					result = "inconclusive"
				end

				client.query("INSERT INTO CombatLog(HouseID, BattleID, Result)
	        	VALUES(#{houseId}, #{currentBattleId}, '#{result}')")
			end
		end
		currentBattleId = currentBattleId+ 1
	end

	# Populate options with our initial options
	populate_option_tables(client);
	# Leave bet tables empty, as no bets have been made yet
end

def create_stored_procedures(client)
	client.query("USE testBase")

	client.query("DROP procedure IF EXISTS insert_bet_option")
	client.query("CREATE PROCEDURE insert_bet_option(
	    IN betType VARCHAR(30),
	    IN foreignID INT,
	    IN bookNo INT,
	    OUT output INT)

	ThisProc:BEGIN
		DECLARE currentOptionID INT;

		IF(betType != 'house' AND betType != 'death' AND betType != 'resurrect') THEN
			SET output = -1;
			LEAVE ThisProc;
		END IF;

		INSERT INTO BetOption (BetType, BookNo, Availability) 
	    VALUES (betType, bookNo, 1);
	    
	    SET currentOptionID = LAST_INSERT_ID();
	    
		IF(betType = 'house') THEN
			INSERT INTO HouseOption
	        VALUES (currentOptionID, foreignID);
		ELSEIF(betType = 'death') THEN
			INSERT INTO DeathOption
	        VALUES (currentOptionID, foreignID);
		ELSEIF(betType = 'resurrect') THEN
			INSERT INTO ResurrectOption
	        VALUES(currentOptionID, foreignID);
	    END IF;
	    
		SET output = 0;
	END")


	client.query("DROP procedure IF EXISTS turn_off_bet_availability")
	client.query("CREATE PROCEDURE turn_off_bet_availability(
	    IN inputBetType VARCHAR(30),
	    IN currentBookNo INT,
	    OUT output INT)

	ThisProc:BEGIN
		DECLARE numMatchingOptions INT;
		DECLARE numAvailable INT;

		SET numMatchingOptions = (SELECT COUNT(BookNo)
									FROM BetOption
									WHERE BetType = inputBetType AND BookNo = currentBookNo);

		SET numAvailable = (SELECT COUNT(BookNo)
								FROM BetOption
								WHERE BetType = inputBetType AND BookNo = currentBookNo 
								AND Availability = 1);


		IF(numAvailable > 0 AND numAvailable < numMatchingOptions) THEN
			SET output = -1;
			LEAVE ThisProc;
		END IF;

		/* Bet was already resolved, so nothing to update. */
		IF(numAvailable = 0) THEN
			SET output = 1;
			LEAVE ThisProc;
		END IF;

		/* Bet not yet resolved, so update relevant bet options to indicate that bet
		is resolved */
		UPDATE BetOption
		SET Availability = 0
		WHERE BetType = inputBetType AND bookNo = currentBookNo;

		SET output = 0;
	END")
	
	client.query("DROP procedure IF EXISTS turn_on_bet_availability")
	client.query("CREATE PROCEDURE turn_on_bet_availability(
	    IN inputBetType VARCHAR(30),
	    IN currentBookNo INT,
	    OUT output INT)

	ThisProc:BEGIN
		DECLARE numMatchingOptions INT;
		DECLARE numAvailable INT;

		SET numMatchingOptions = (SELECT COUNT(BookNo)
									FROM BetOption
									WHERE BetType = inputBetType AND BookNo = currentBookNo);

		SET numAvailable = (SELECT COUNT(BookNo)
								FROM BetOption
								WHERE BetType = inputBetType AND BookNo = currentBookNo 
								AND Availability = 1);


		IF(numAvailable > 0 AND numAvailable < numMatchingOptions) THEN
			SET output = -1;
			LEAVE ThisProc;
		END IF;

		/* Bet is already on, so nothing to update. */
		IF(numAvailable = numMatchingOptions) THEN
			SET output = 1;
			LEAVE ThisProc;
		END IF;

		/* Bet already resolved, so update relevant bet options to indicate that bet
		is now active again */
		UPDATE BetOption
		SET Availability = 1
		WHERE BetType = inputBetType AND bookNo = currentBookNo;

		SET output = 0;
	END")

	client.query("DROP procedure IF EXISTS update_person")
	client.query("CREATE PROCEDURE update_person(
	    IN charName VARCHAR(80),
	    IN houseName VARCHAR(80),
	    IN newTitle VARCHAR(60),
	    IN newIsAlive SMALLINT,
	   	IN currentBookNo INT,
	    OUT output INT)

	ThisProc:BEGIN
		DECLARE currentIsAlive INT;
		DECLARE matchingCharID INT;
		DECLARE matchingHouseID INT;
		DECLARE optionCheck INT;
		DECLARE updateStatus INT;
		DECLARE betsAffected INT;

		SET matchingCharID = (SELECT CharID
								FROM Person
								Where Name = charName);

		IF(matchingCharID IS NULL) THEN
			SET output = -1;
		 	LEAVE ThisProc;
		END IF;

		SET currentIsAlive = (SELECT IsAlive
								FROM Person
								WHERE CharID = matchingCharID);

		IF(currentIsAlive = 1 AND newIsAlive = 0 AND currentBookNo = -1) THEN
			SET output = -2;
			LEAVE ThisProc;
		END IF;

		IF(houseName = ' ') THEN
			SET matchingHouseID = (SELECT HouseID
								FROM Person
								WHERE CharID = matchingCharID);
		ELSE
			SET matchingHouseID = (SELECT H.HouseID
									FROM House AS H
									Where H.HouseName = houseName);
		END IF;

		UPDATE Person
	    SET HouseID = matchingHouseID,
	    	Title = newTitle,
	    	IsAlive = newIsAlive
	    WHERE CharID = matchingCharID;

	    IF(currentIsAlive != newIsAlive AND newIsAlive = 1) THEN
	    	SET optionCheck = (SELECT COUNT(*)
	    						FROM ResurrectOption AS R, BetOption AS B
	    						WHERE R.OptionID = B.OptionID AND R.CharID = matchingCharID
	    							  AND B.BookNo = currentBookNo);

	    	IF(optionCheck = 0) THEN
	    		SET betsAffected = 0;
	    	ELSE 
		    	CALL turn_off_bet_availability('resurrect', currentBookNo, updateStatus);

		    	IF(updateStatus = 0) THEN
		    		SET betsAffected = 1;
		    	ELSE
		    		SET betsAffected = 0;
		    	END IF;
		    END IF;

	    	INSERT INTO Event(ParticipantID, Description, BookOccurred, ChangedBets)
	    	VALUES(matchingCharID, 'resurrect', curretnBookNo, betsAffected);
	    ELSEIF(currentIsAlive != newIsAlive AND newIsAlive = 0) THEN
	    	SET optionCheck = (SELECT COUNT(*)
	    						FROM DeathOption AS D, BetOption AS B
	    						WHERE D.OptionID = B.OptionID AND D.CharID = matchingCharID
	    							  AND B.BookNo = currentBookNo);

	    	IF(optionCheck = 0) THEN
	    		SET betsAffected = 0;
	    	ELSE 
		    	CALL turn_off_bet_availability('death', currentBookNo, updateStatus);

		    	IF(updateStatus = 0) THEN
		    		SET betsAffected = 1;
		    	ELSE
		    		SET betsAffected = 0;
		    	END IF;
		    END IF;

	    	INSERT INTO Event(ParticipantID, Description, BookOccurred, ChangedBets)
	    	VALUES(matchingCharID, 'death', curretnBookNo, betsAffected);
	    END IF;

		SET output = 0;
	END")

	client.query("DROP procedure IF EXISTS update_house")
	client.query("CREATE PROCEDURE update_house(
	    IN inputHouseName VARCHAR(80),
	    IN inputWonThrone SMALLINT,
	   	IN currentBookNo INT,
	    OUT output INT)

	ThisProc:BEGIN
		DECLARE matchingHouseID INT;
		DECLARE throneWinnersCount INT;
		DECLARE oldWonThrone SMALLINT;
		DECLARE optionCheck INT;
		DECLARE checkOption INT;
		DECLARE updateStatus INT;
		DECLARE betsAffected INT;

		SET oldWonThrone = (SELECT WonThrone
								FROM House
								WHERE HouseID = matchingHouseID);

		SET matchingHouseID = (SELECT HouseID
								FROM House
								WHERE HouseName = inputHouseName);

		SET throneWinnersCount = (SELECT COUNT(*)
									FROM House
									Where WonThrone = 1);

		IF(throneWinnersCount > 0 AND inputWonThrone = 1 AND oldWonThrone != inputWonThrone) THEN
			SET output = -1;
		 	LEAVE ThisProc;
		END IF;

		IF(oldWonThrone = 0 AND newWonThrone= 1 AND currentBookNo = -1) THEN
			SET output = -2;
			LEAVE ThisProc;
		END IF;

		UPDATE House
		SET WonThrone = inputWonThrone
		WHERE HouseID = matchingHouseID;

	    IF(oldWonThrone != newWonThrone AND newWonThrone = 1) THEN
	    	SET optionCheck = (SELECT COUNT(*)
	    						FROM HouseOption AS H, BetOption AS B
	    						WHERE R.OptionID = B.OptionID AND R.CharID = matchingCharID
	    							  AND B.BookNo = currentBookNo);

	    	IF(optionCheck = 0) THEN
	    		SET betsAffected = 0;
	    	ELSE 
		    	CALL turn_off_bet_availability('house', currentBookNo, updateStatus);

		    	IF(updateStatus = 0) THEN
		    		SET betsAffected = 1;
		    	ELSE
		    		SET betsAffected = 0;
		    	END IF;
		    END IF;

	    	INSERT INTO Event(ParticipantID, Description, BookOccurred, ChangedBets)
	    	VALUES(matchingCharID, 'house', curretnBookNo, betsAffected);
	    END IF;

		SET output = 0;
	END")

	client.query("DROP procedure IF EXISTS delete_event")
	client.query("CREATE PROCEDURE delete_event(
	    IN removeOptionID INT,
	    OUT output INT)

	ThisProc:BEGIN
		DECLARE eventCount INT;
		DECLARE wereBetsAffected INT;
		DECLARE eventType VARCHAR(30);
		DECLARE bookNo INT;
		DECLARE foreignID INT;
		DECLARE betsAffected INT;
		DECLARE eventToModify INT;
		DECLARE doBetsNeedUpdate INT;
		DECLARE updateStatus INT;

		SET eventCount = (SELECT COUNT(*)
							FROM Event
							Where OptionID = removeOptionID);

		IF(eventCount = 0) THEN
			SET output = -1;
		 	LEAVE ThisProc;
		END IF;

		SET wereBetsAffected = (SELECT ChangedBets
									FROM Event
									WHERE OptionID = removeOptionID);

		SET eventType = (SELECT Description
							FROM Event
							WHERE OptionID = removeOptionID);

		SET bookNo = (SELECT BookOccurred
						FROM Event
						WHERE OptionID = removeOptionID);


		DELETE FROM Event
		WHERE OptionID = removeOptionID;

		IF(eventType = 'house') THEN
			UPDATE House
			SET WonThrone = 0
			WHERE HouseID = foreignID;

			SET eventToModify =	SELECT MIN(E.EventID)
									FROM HouseOption AS H, BetOption AS B, Event AS E
									WHERE H.OptionID = B.OptionID AND H.HouseID = E.ParticipantID
										  AND E.BetType = 'house' AND E.BookOccurred = bookNo
		ELSEIF(eventType = 'death') THEN
			UPDATE Person
			SET IsAlive = 1
			WHERE CharID = foreignID;

			SET eventToModify =	SELECT MIN(E.EventID)
									FROM DeathOption AS H, BetOption AS B, Event AS E
									WHERE H.OptionID = B.OptionID AND H.HouseID = E.ParticipantID
										  AND E.BetType = 'house' AND E.BookOccurred = bookNo
		ELSE
			UPDATE Person
			SET IsAlive = 0
			WHERE CharID = foreignID;

			SET eventToModify =	SELECT MIN(E.EventID)
									FROM ResurrectOption AS H, BetOption AS B, Event AS E
									WHERE H.OptionID = B.OptionID AND H.HouseID = E.ParticipantID
										  AND E.BetType = 'house' AND E.BookOccurred = bookNo
		END IF;

		IF(wereBetsAffected = 1) THEN

			CALL turn_on_bet_availability(eventType, bookNo, eventStatus); 
		END IF;

		IF(eventStatus != 0) THEN
			SET output = -3;
			LEAVE ThisProc;
		END IF;

		SET output = 0;
	END")
end

# Parse the data tables
people = CSV.read('character.csv')
stats = CSV.read('prediction.csv')
battles = CSV.read('battles.csv')

# Connect to client
Mysql2::Client.default_query_options.merge!(:as => :array)
client = Mysql2::Client.new(:host => "192.168.91.2",:username => "testuser", :password => "mysqltest")

# Create the database and associated tables/views
databaseName = "testBase"
if mode == "create" 
	create_database(client, databaseName)
	client.query("USE #{databaseName}")
	drop_tables(client)
	create_tables_and_views(client)
	create_stored_procedures(client)
	# Populate the database
	populate_tables(client, people, stats, battles)\
else # How do this considering populate dumps it in special way
	client.query("USE #{databaseName}")
end

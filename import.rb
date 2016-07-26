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
	client.query("DROP TABLE IF EXISTS Bet")
	client.query("DROP TABLE IF EXISTS CombatLog")
	client.query("DROP TABLE IF EXISTS Person")
	client.query("DROP TABLE IF EXISTS House")
	client.query("DROP TABLE IF EXISTS Battle")
	client.query("DROP TABLE IF EXISTS Event")
end

def create_tables_and_views(client)
	# Tables

	# Note: House has multiple derived attributes that are expressed in a view on House involving both
	# the combat log and the Person and Death tables.
	client.query("CREATE TABLE IF NOT EXISTS House (
					HouseID INT PRIMARY KEY,
					HouseName VARCHAR(80) NOT NULL UNIQUE,
					WonThrone SMALLINT NOT NULL,
					IsOption SMALLINT NOT NULL DEFAULT 0,
					Odds DECIMAL(10, 3),
					CHECK(WonThrone = 0 OR WonThrone = 1),
					CHECK(IsOption = 0 OR IsOption = 1))")

	client.query("CREATE TABLE IF NOT EXISTS Person (
					CharID INT PRIMARY KEY, 
					Name varchar(80) NOT NULL UNIQUE,
					IsAlive SMALLINT NOT NULL,
					HouseID INT, 
					Gender INT NOT NULL, 
					Title varchar(60), 
					DeathProbability DECIMAL(10, 3) NOT NULL,
					Popularity DECIMAL(10, 6) NOT NULL,
					BookOfDeath SMALLINT,
					IsOption INT NOT NULL DEFAULT 0,
					Odds DECIMAL(10, 3),
					FOREIGN KEY(HouseID) REFERENCES House(HouseID),
					CHECK(IsAlive = 0 OR IsAlive = 1),
					CHECK(Gender = 0 OR Gender = 1),
					CHECK(DeathProbability <= 1),
					CHECK(WonThrone = 0 OR WonThrone = 1),
					CHECK(IsOption = 0 OR IsOption = 1))")

	client.query("CREATE TABLE IF NOT EXISTS Battle (
					BattleID INT PRIMARY KEY, 
					BattleName VARCHAR(80) NOT NULL, 
					City VARCHAR(60), 
					Year INT,
					CHECK(Year > 296))")

	client.query("CREATE TABLE IF NOT EXISTS CombatLog (
					HouseID INT NOT NULL, 
					BattleID INT NOT NULL, 
					Result VARCHAR(60), 
					PRIMARY KEY(HouseID, BattleID),
					FOREIGN KEY(HouseID) REFERENCES House(HouseID), 
					FOREIGN KEY(BattleID) REFERENCES Battle(BattleID))")

	client.query("CREATE TABLE IF NOT EXISTS Event (
					EventID INT AUTO_INCREMENT PRIMARY KEY, 
					Description VARCHAR(80) NOT NULL,
					ParticipantID INT NOT NULL,
					ParticipantName VARCHAR(80) NOT NULL,
					BookOccurred SMALLINT NOT NULL,
					CHECK(ChangedBets = 0 OR ChangedBets = 1),
					CHECK(BookOccurred > 0 AND BookOccurred < 11))")

	client.query("CREATE TABLE IF NOT EXISTS Bet (
					BetID INT AUTO_INCREMENT PRIMARY KEY,
					OptionID INT NOT NULL,
					OptionName VARCHAR(80) NOT NULL,
					BetType VARCHAR(80) NOT NULL,
					BookNo SMALLINT NOT NULL, 
					UserEmail VARCHAR(100) NOT NULL,
					BetAmount DECIMAL(10, 2) NOT NULL,
					CHECK(BetAmount > 1.00))")

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

	client.query("CREATE OR REPLACE VIEW HouseBattleWinStats (
					HouseID, HouseName, NumBattlesWon)
					AS SELECT H.HouseID, H.HouseName, COUNT(BattleID)
							FROM House AS H, CombatLog AS L
							WHERE H.HouseID = L.HouseID AND result = 'win'
							GROUP BY HouseID")

	client.query("CREATE OR REPLACE VIEW HouseBattleInvolvedStats (
					HouseID, HouseName, NumBattlesInvolved)
					AS SELECT H.HouseID, H.HouseName, COUNT(BattleID)
							FROM House AS H, CombatLog AS L
							WHERE H.HouseID = L.HouseID
							GROUP BY HouseID")
end

def calculate_and_insert_death_odds(client, charIDs, bookNo)
	charDeathProb = Hash.new()
	totalProb = 0
	charIDs.each do |id|
		result = client.query("SELECT DeathProbability
								FROM Person
								WHERE CharID = #{id}")
		
		result.each do |val|
			charDeathProb.merge!({id => val[0]})
			totalProb += val[0]
		end
	end

	charDeathProb.each do |id, probability|
		relativeProbability = (probability / totalProb).to_f
		odds = 1 / (relativeProbability) - 1
		odds = odds.round

		client.query("UPDATE Person
					  SET Odds = #{odds}
					  WHERE CharID = #{id}")
	end
end

def calculate_and_insert_throne_odds(client, houseIDs, bookNo) 
	houseWinProb = Hash.new()
	totalProb = 0
	houseIDs.each do |id|
		result = client.query("SELECT D.NumMembersDead, M.NumTotalMembers
								FROM HouseDeathStats AS D, HouseMembership AS M
								WHERE D.HouseID = #{id}
									  AND M.HouseID = #{id}")
	
		currentNumDead = 0
		currentNumMembers = 0

		result.each do |val|
			currentNumDead = val[0]
			currentNumMembers = val[1]
		end

		deathDecimal = currentNumDead.to_f / currentNumMembers.to_f

		rawProbability = (1 - deathDecimal)
		totalProb += rawProbability
		houseWinProb.merge!({id => rawProbability})\
	end

	houseWinProb.each do |id, probability|
		relativeProbability = (probability / totalProb).to_f
		odds = 1 / (relativeProbability) - 1
		odds = odds.round

		client.query("UPDATE House
					  SET Odds = #{odds}
					  WHERE HouseID = #{id}")
	end
end

def calculate_and_insert_resurrect_odds(client, charIDs, bookNo)
	charResProb = Hash.new()
	totalProb = 0
	charIDs.each do |id|
		result = client.query("SELECT Popularity, BookOfDeath
								FROM Person
								WHERE CharID = #{id}")
		
		currentPopularity = 0
		bookOfDeath = 0
		result.each do |val|
			currentPopularity = val[0]
			bookOfDeath = val[1]
		end

		numBooksSinceDeath = bookNo - bookOfDeath

		rawProbability = currentPopularity / numBooksSinceDeath
		charResProb.merge!({id => rawProbability})
		totalProb += rawProbability
	end

	charResProb.each do |id, probability|
		relativeProbability = (probability / totalProb).to_f
		odds = 1 / (relativeProbability) - 1
		odds = odds.round

		client.query("UPDATE Person
					  SET Odds = #{odds}
					  WHERE CharID = #{id}")
	end
end

def populate_option_tables(client)
	bookNo = 6

	# Populate options on which living character will be resurrected
	client.query("UPDATE Person
					SET IsOption = 1
					WHERE Name IN ('Arya Stark', 'Daenerys Targaryen', 'Jaime Lannister', 
						'Varys', 'Theon Greyjoy', 'Cersei Lannister', 'Barristan Selmy',
						'Bran Stark', 'Margaery Tyrell', 'Petyr Baelish',
						'Tyrion Lannister', 'Roose Bolton', 'Davos Seaworth',
						'Samwell Tarly', 'Jorah Mormont')")

	deathQuery = client.query("SELECT CharID
								FROM Person
								WHERE Name IN ('Arya Stark', 'Daenerys Targaryen', 'Jaime Lannister', 
									'Varys', 'Theon Greyjoy', 'Cersei Lannister', 'Barristan Selmy',
									'Bran Stark', 'Margaery Tyrell', 'Petyr Baelish',
									'Tyrion Lannister', 'Roose Bolton', 'Davos Seaworth',
									'Samwell Tarly', 'Jorah Mormont')")


	deathIDs = []
	deathQuery.each do |val|
		deathIDs << val[0]
	end

	calculate_and_insert_death_odds(client, deathIDs, bookNo)


	# Populate options on which dead character will be resurrected
	client.query("UPDATE Person
					SET IsOption = 1
					WHERE Name IN ('Eddard Stark', 'Joffrey Baratheon', 
					'Drogo', 'Viserys Targaryen', 'Robb Stark',
					'Oberyn Martell', 'Quentyn Martell', 'Renly Baratheon',
					'Jeor Mormont', 'Janos Slynt', 'Tywin Lannister',
					'Kevan Lannister', 'Gregor Clegane', 'Sandor Clegane')")

	resurrectQuery = client.query("SELECT CharID
									FROM Person
									WHERE Name IN ('Eddard Stark', 'Joffrey Baratheon', 
									'Drogo', 'Viserys Targaryen', 'Robb Stark',
									'Oberyn Martell', 'Quentyn Martell', 'Renly Baratheon',
									'Jeor Mormont', 'Janos Slynt', 'Tywin Lannister',
									'Kevan Lannister', 'Gregor Clegane', 'Sandor Clegane')")
	
	resurrectIDs = []
	resurrectQuery.each do |val|
		resurrectIDs << val[0]
	end

	calculate_and_insert_resurrect_odds(client, resurrectIDs, bookNo)


	# Populate options on which house will claim throne

	client.query("UPDATE House
					SET IsOption = 1
					WHERE HouseID IN (SELECT D.HouseID
										FROM HouseDeathStats AS D)")

	houseQuery = client.query("SELECT HouseID
									FROM House
									WHERE HouseID IN (SELECT D.HouseID
														FROM HouseDeathStats AS D)")
	houseIDs = []
	houseQuery.each do |val|
		houseIDs << val[0]
	end

	calculate_and_insert_throne_odds(client, houseIDs, bookNo)
end

def populate_tables(client, people, stats, battles) 
	# Create a list of names from the prediction csv file. We only want to add names that appear in both
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

		# Given our source's formatting, there may be two identical names like "Stark" and
		# "House Stark." To avoid this issue, we will split each name by " " and, if the
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
		if currentName != "None"
			houseIdMapping.merge!({currentName => houseId})

			currentName = remove_bad_char(currentName)

			client.query("INSERT INTO House(HouseID, HouseName, WonThrone)
				          VALUE(#{houseId}, '#{currentName}', 0)")
		end
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

			bookOfDeath = person[3]
			if bookOfDeath == nil
				bookOfDeath = -1
			end

			personIsAlive = person[3] != nil ? 0 : 1
			probability = stats[statRow][4]
			popularity = stats[statRow][31]

			if houseName != "None"
				houseId = houseIdMapping.fetch(houseName)

				client.query("INSERT INTO Person(CharID, IsAlive, HouseID, Name, 
		        	Gender, Title, DeathProbability, Popularity, BookOfDeath) 
			        VALUES(#{currentIdValue}, #{personIsAlive}, #{houseId}, '#{name}',
			         #{gender}, '#{title}', #{probability}, #{popularity}, #{bookOfDeath})")
			else
				client.query("INSERT INTO Person(CharID, IsAlive, Name, 
		        	Gender, Title, DeathProbability, Popularity, BookOfDeath) 
			        VALUES(#{currentIdValue}, #{personIsAlive}, '#{name}',
			         #{gender}, '#{title}', #{probability}, #{popularity}, #{bookOfDeath})")
			end


			currentIdValue = currentIdValue + 1
		end
	end

	# Insert values into Battle table
	currentIdValue = 1
	battles.each do |battle|
		# Insert battle into Battle
		battleName = battle[0]
		battleName = remove_bad_char(battleName)

		location = battle[22]
		location = remove_bad_char(location)

		year = battle[1].to_i

		client.query("INSERT INTO Battle (BattleID, BattleName, City, Year)
			          VALUE(#{currentIdValue}, '#{battleName}' ,'#{location}',#{year})")


		# Insert participating houses into CombatLog

		# Compile a list of all attackers from battles document
		firstAttackIndex = 5
		lastAttackIndex = 8
		attackers = []
		for j in firstAttackIndex..lastAttackIndex
			if (battle[j] != nil)
				attackers << battle[j]
			end
		end

		# Compile a list of all defenders from battles document
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
	        	VALUES(#{houseId}, #{currentIdValue}, '#{result}')")
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
	        	VALUES(#{houseId}, #{currentIdValue}, '#{result}')")
			end
		end
		currentIdValue = currentIdValue + 1
	end


	# Populate options with our initial options
	populate_option_tables(client);
	# Leave bet tables empty, as no bets have been made yet
end

def create_log_and_update_person(client)
	client.query("DROP procedure IF EXISTS log_and_update_person")
	client.query("CREATE PROCEDURE log_and_update_person(
			IN nameToChange VARCHAR(80),
			IN newHouseName VARCHAR(80),
			IN newTitle VARCHAR(80),
			IN newIsAlive SMALLINT,
			IN newDeathProb DECIMAL(10, 3),
			IN newPopularity DECIMAL(10, 3),
			IN currentBookNo SMALLINT,
			OUT output INT)

		ThisProc:BEGIN
			DECLARE matchingCharID INT;
			DECLARE matchingHouseID INT;
			DECLARE matchingEventCount INT;
			DECLARE deathBookNo SMALLINT;
			DECLARE oldIsAlive SMALLINT;
			DECLARE willLogEvent SMALLINT;
			DECLARE oldEventDescription VARCHAR(80);
			DECLARE newEventDescription VARCHAR(80);

			SET matchingCharID = (SELECT CharID
									FROM Person
									Where Name = nameToChange);

			SET oldIsAlive = (SELECT IsAlive
								FROM Person
								WHERE CharID = matchingCharID);

			/* Validate input. */

			IF(matchingCharID IS NULL) THEN
				SET output = -1;
			 	LEAVE ThisProc;
			END IF;

			IF(newIsAlive != 0 AND newIsAlive != 1) THEN
				SET newIsAlive = currentIsAlive;
				SET willLogEvent = 0;
			ELSE
				SET willLogEvent = 1;
			END IF;

			SET matchingHouseID = (SELECT H.HouseID
									FROM House AS H
									Where H.HouseName = newHouseName);

			IF(matchingHouseID IS NULL) THEN
				SET matchingHouseID = (SELECT HouseID
										FROM Person
										WHERE CharID = matchingCharID);
			END IF;

			IF(newTitle = '') THEN
				SET newTitle = (SELECT Title
									FROM Person
									WHERE CharID = matchingCharID);
			END IF;

			IF(!(newDeathProb > 0 AND newDeathProb <= 1)) THEN
				SET newDeathProb = (SELECT DeathProbability
										FROM Person
										WHERE CharID = matchingCharID);
			END IF;

			IF(!(newPopularity > 0 AND newPopularity <= 1)) THEN
				SET newPopularity = (SELECT Popularity
										FROM Person
										WHERE CharID = matchingCharID);
			END IF;

			IF(newIsAlive = 0) THEN
				SET deathBookNo = currentBookNo;
			ELSE
				SET deathBookNo = (SELECT BookOfDeath
										FROM Person
										WHERE CharID = matchingCharID);
			END IF;


			/* Perform UPDATE. */

			UPDATE Person
		    SET HouseID = matchingHouseID,
		    	Title = newTitle,
		    	IsAlive = newIsAlive,
		    	DeathProbability = newDeathProb,
		    	Popularity = newPopularity,
		    	BookOfDeath = deathBookNo
		    WHERE CharID = matchingCharID;

		    /* Check if an event needs to be logged. */

		    /* No input for IsAlive, so state of character at end of book is unknown.
		       Hence, no need to log an event. */
		    IF (willLogEvent = 0) THEN
		    	SET output = 0;
		    	LEAVE ThisProc;
		    END IF;

		    SET matchingEventCount = (SELECT Count(*)
		    							FROM Event
		    							WHERE ParticipantName = nameToChange
		    								  AND BookOccurred = currentBookNo);


		    SET oldEventDescription = (SELECT Description
		    							FROM Event
		    							WHERE ParticipantName = nameToChange
		    								  AND BookOccurred = currentBookNo);

		    /* IsAlive has not changed and an event already encompasses an update
		       to the state of IsAlive. Hence, no need to log an event. */
		    IF(oldIsAlive = newIsAlive AND matchingEventCount > 0) THEN
		    	SET output = 0;
		    	LEAVE ThisProc;
		    END IF;

		    /* IsAlive has changed, so remove old conflicting event in preparation
		       for logging a new one. */
		    IF(oldIsAlive != newIsAlive AND matchingEventCount > 0) THEN
		    	DELETE FROM Event
		    	WHERE ParticipantName = nameToChange
		    		  AND BookOccurred = currentBookNo;
		    END IF;


		    /* No event logged for update to IsAlive. Set event Description to 
		       match the state of newIsAlive relative to oldIsAlive. */
		    IF(oldEventDescription IS NULL) THEN
		    	IF(oldIsAlive = 1 AND newIsAlive = 0) THEN
		    		SET newEventDescription = 'death';
		    	ELSEIF(oldIsAlive = 1 AND newIsAlive = 1) THEN
		    		SET newEventDescription = 'survived';
		    	ELSEIF(oldIsAlive = 0 AND newIsAlive = 0) THEN
		    		SET newEventDescription = 'remained dead';
		    	ELSE
		    		SET newEventDescription = 'resurrect';
		    	END IF;
		    /* A formerly conflicting event was deleted, so our new Description
		       will be the opposite of what was previously in the Event log. */
		    ELSEIF(oldEventDescription = 'survived') THEN
		    	SET newEventDescription = 'death';
		    ELSEIF(oldEventDescription = 'death') THEN
		    	SET newEventDescription = 'survived';
		    ELSEIF(oldEventDescription = 'remained dead') THEN
		    	SET newEventDescription = 'resurrect';
		    ELSEIF(oldEventDescription = 'resurrect') THEN
		    	SET newEventDescription = 'remained dead';
		    END IF;

		    INSERT INTO Event(Description, ParticipantName, ParticipantID, BookOccurred)
		    VALUES(newEventDescription, nameToChange, matchingCharID, currentBookNo);

		    SET output = 0;
		END")
end

def create_log_and_update_house(client)
	client.query("DROP procedure IF EXISTS log_and_update_house")
	client.query("CREATE PROCEDURE log_and_update_house(
			IN inputHouseName VARCHAR(80),
		    IN newWonThrone SMALLINT,
		   	IN currentBookNo INT,
		    OUT output INT)

		ThisProc:BEGIN
			DECLARE matchingHouseID INT;
			DECLARE oldWonThrone SMALLINT;
			DECLARE willLogEvent INT;
			DECLARE matchingEventCount INT;
			DECLARE oldEventDescription VARCHAR(80);
			DECLARE newEventDescription VARCHAR(80);

			SET matchingHouseID = (SELECT HouseID
									FROM House
									WHERE HouseName = inputHouseName);

			SET oldWonThrone = (SELECT WonThrone
									FROM House
									WHERE HouseID = matchingHouseID);
			/* Validate input */

			IF(newWonThrone != 0 AND newWonThrone != 1) THEN
				SET newWonThrone = oldWonThrone;
				SET willLogEvent = 0;
			ELSE
				SET willLogEvent = 1;
			END IF;

			/* Perform update */

			UPDATE House
			SET WonThrone = newWonThrone
			WHERE HouseID = matchingHouseID;

		    /* Check if an event needs to be logged. */

		    /* No input for WonThrone, so state of house at end of book is unknown.
		       Hence, no need to log an event. */
		    IF (willLogEvent = 0) THEN
		    	SET output = 0;
		    	LEAVE ThisProc;
		    END IF;

		    SET matchingEventCount = (SELECT Count(*)
		    							FROM Event
		    							WHERE ParticipantName = inputHouseName
		    								  AND BookOccurred = currentBookNo);


		    SET oldEventDescription = (SELECT Description
		    							FROM Event
		    							WHERE ParticipantName = inputHouseName
		    								  AND BookOccurred = currentBookNo);

		    /* WonThrone has not changed and an event already encompasses an update
		       to the state of WonThrone. Hence, no need to log an event. */
		    IF(oldWonThrone = newWonThrone AND matchingEventCount > 0) THEN
		    	SET output = 0;
		    	LEAVE ThisProc;
		    END IF;

		    /* WonThrone has changed, so remove old conflicting event in preparation
		       for logging a new one. */
		    IF(oldWonThrone != newWonThrone AND matchingEventCount > 0) THEN
		    	DELETE FROM Event
		    	WHERE ParticipantName = inputHouseName
		    		  AND BookOccurred = currentBookNo;
		    END IF;


		    /* No event logged for update to WonThrone. Set event Description to 
		       match the state of newWonThrone relative to oldWonThrone. */
		    IF(oldEventDescription IS NULL) THEN
		    	IF(oldWonThrone = 0 AND newWonThrone = 0) THEN
		    		SET newEventDescription = 'remained throneless';
		    	ELSE
		    		SET newEventDescription = 'throne';
		    	END IF;
		    /* A formerly conflicting event was deleted, so our new Description
		       will be the opposite of what was previously in the Event log. */
		    ELSEIF(oldEventDescription = 'remained throneless') THEN
		    	SET newEventDescription = 'throne';
		    ELSEIF(oldEventDescription = 'throne') THEN
		    	SET newEventDescription = 'remained throneless';
		    END IF;

		    IF (newEventDescription = 'throne') THEN
				UPDATE House
				SET IsOption = 0
				WHERE HouseID = matchingHouseID;
			ELSE
				UPDATE House
				SET IsOption = 1
				WHERE HouseID = matchingHouseID;
			END IF;

		    INSERT INTO Event(Description, ParticipantName, ParticipantID, BookOccurred)
		    VALUES(newEventDescription, inputHouseName, matchingHouseID, currentBookNo);

		    SET output = 0;
		END")
end
# def create_insert_bet_option(client)
# 	client.query("DROP procedure IF EXISTS insert_bet_option")
# 	client.query("CREATE PROCEDURE insert_bet_option(
# 	    IN betType VARCHAR(30),
# 	    IN foreignID INT,
# 	    IN bookNo INT,
# 	    OUT output INT)

# 	ThisProc:BEGIN
# 		DECLARE currentOptionID INT;

# 		IF(betType != 'throne' AND betType != 'death' AND betType != 'resurrect') THEN
# 			SET output = -1;
# 			LEAVE ThisProc;
# 		END IF;

# 		INSERT INTO BetOption (BetType, BookNo, Availability) 
# 	    VALUES (betType, bookNo, 1);
	    
# 	    SET currentOptionID = LAST_INSERT_ID();
	    
# 		IF(betType = 'throne') THEN
# 			INSERT INTO ThroneOption
# 	        VALUES (currentOptionID, foreignID);
# 		ELSEIF(betType = 'death') THEN
# 			INSERT INTO DeathOption
# 	        VALUES (currentOptionID, foreignID);
# 		ELSEIF(betType = 'resurrect') THEN
# 			INSERT INTO ResurrectOption
# 	        VALUES(currentOptionID, foreignID);
# 	    END IF;
	    
# 		SET output = 0;
# 	END")
# end

# def create_turn_off_bet_availability(client)
# 	client.query("DROP procedure IF EXISTS turn_off_bet_availability")
# 	client.query("CREATE PROCEDURE turn_off_bet_availability(
# 	    IN inputBetType VARCHAR(30),
# 	    IN currentBookNo INT,
# 	    OUT output INT)

# 	ThisProc:BEGIN
# 		DECLARE numMatchingOptions INT;
# 		DECLARE numAvailable INT;

# 		SET numMatchingOptions = (SELECT COUNT(BookNo)
# 									FROM BetOption
# 									WHERE BetType = inputBetType AND BookNo = currentBookNo);

# 		SET numAvailable = (SELECT COUNT(BookNo)
# 								FROM BetOption
# 								WHERE BetType = inputBetType AND BookNo = currentBookNo 
# 								AND Availability = 1);


# 		IF(numAvailable > 0 AND numAvailable < numMatchingOptions) THEN
# 			SET output = -1;
# 			LEAVE ThisProc;
# 		END IF;

# 		/* Bet was already resolved, so nothing to update. */
# 		IF(numAvailable = 0) THEN
# 			SET output = 1;
# 			LEAVE ThisProc;
# 		END IF;

# 		/* Bet not yet resolved, so update relevant bet options to indicate that bet
# 		is resolved */
# 		UPDATE BetOption
# 		SET Availability = 0
# 		WHERE BetType = inputBetType AND bookNo = currentBookNo;

# 		SET output = 0;
# 	END")
# end

# def create_turn_on_bet_availability(client)
# 	client.query("DROP procedure IF EXISTS turn_on_bet_availability")
# 	client.query("CREATE PROCEDURE turn_on_bet_availability(
# 	    IN inputBetType VARCHAR(30),
# 	    IN currentBookNo INT,
# 	    OUT output INT)

# 	ThisProc:BEGIN
# 		DECLARE numMatchingOptions INT;
# 		DECLARE numAvailable INT;

# 		SET numMatchingOptions = (SELECT COUNT(BookNo)
# 									FROM BetOption
# 									WHERE BetType = inputBetType AND BookNo = currentBookNo);

# 		SET numAvailable = (SELECT COUNT(BookNo)
# 								FROM BetOption
# 								WHERE BetType = inputBetType AND BookNo = currentBookNo 
# 								AND Availability = 1);


# 		IF(numAvailable > 0 AND numAvailable < numMatchingOptions) THEN
# 			SET output = -1;
# 			LEAVE ThisProc;
# 		END IF;

# 		/* Bet is already on, so nothing to update. */
# 		IF(numAvailable = numMatchingOptions) THEN
# 			SET output = 1;
# 			LEAVE ThisProc;
# 		END IF;

# 		/* Bet already resolved, so update relevant bet options to indicate that bet
# 		is now active again */
# 		UPDATE BetOption
# 		SET Availability = 1
# 		WHERE BetType = inputBetType AND bookNo = currentBookNo;

# 		SET output = 0;
# 	END")
# end

# def create_update_person(client)
# 	client.query("DROP procedure IF EXISTS update_person")
# 	client.query("CREATE PROCEDURE update_person(
# 	    IN charName VARCHAR(80),
# 	    IN houseName VARCHAR(80),
# 	    IN newTitle VARCHAR(60),
# 	    IN newIsAlive SMALLINT,
# 	    IN newDeathProb DECIMAL(10, 3),
# 	    IN newPopularity DECIMAL(10, 6),
# 	   	IN currentBookNo INT,
# 	    OUT output INT)

# 	ThisProc:BEGIN
# 		DECLARE oldIsAlive INT;
# 		DECLARE matchingCharID INT;
# 		DECLARE matchingHouseID INT;
# 		DECLARE deathBookNo INT;
# 		DECLARE optionCheck INT;
# 		DECLARE newEventID INT;
# 		DECLARE newEventType VARCHAR(20);
# 		DECLARE updateStatus INT;
# 		DECLARE wereBetsAffected INT;

# 		SET matchingCharID = (SELECT CharID
# 								FROM Person
# 								Where Name = charName);

# 		SET oldIsAlive = (SELECT CharID
# 								FROM Person
# 								WHERE CharID = matchingCharID);


# 		/* Validate input. */

# 		IF(matchingCharID IS NULL) THEN
# 			SET output = -1;
# 		 	LEAVE ThisProc;
# 		END IF;

# 		IF(newIsAlive != 0 AND newIsAlive != 1) THEN
# 			SET newIsAlive = (SELECT IsAlive
# 								FROM Person
# 								WHERE CharID = matchingCharID);
# 		END IF;

# 		SET matchingHouseID = (SELECT H.HouseID
# 								FROM House AS H
# 								Where H.HouseName = houseName);
# 		IF(matchingHouseID IS NULL) THEN
# 			SET matchingHouseID = (SELECT HouseID
# 								FROM Person
# 								WHERE CharID = matchingCharID);
# 		END IF;

# 		IF(newTitle IS NULL) THEN
# 			SET newTitle = (SELECT Title
# 								FROM Person
# 								WHERE CharID = matchingCharID);
# 		END IF;

# 		IF(!(newDeathProb > 0 AND newDeathProb <= 1)) THEN
# 			SET newDeathProb = (SELECT DeathProbability
# 									FROM Person
# 									WHERE CharID = matchingCharID);
# 		END IF;

# 		IF(!(newPopularity > 0 AND newPopularity <= 1)) THEN
# 			SET newPopularity = (SELECT Popularity
# 									FROM Person
# 									WHERE CharID = matchingCharID);
# 		END IF;

# 		IF(newIsAlive = 0) THEN
# 			SET deathBookNo = currentBookNo;
# 		ELSE
# 			SET deathBookNo = (SELECT BookOfDeath
# 									FROM Person
# 									WHERE CharID = matchingCharID);
# 		END IF;


# 		/* Perform UPDATE. */

# 		UPDATE Person
# 	    SET HouseID = matchingHouseID,
# 	    	Title = newTitle,
# 	    	IsAlive = newIsAlive,
# 	    	DeathProbability = newDeathProb,
# 	    	Popularity = newPopularity,
# 	    	BookOfDeath = deathBookNo
# 	    WHERE CharID = matchingCharID;


# 	    /* Log UPDATE into EVENT table (if necessary). */

# 	    IF(oldIsAlive != newIsAlive AND newIsAlive = 1) THEN
# 	        SET newEventType = 'resurrect';

# 	    	SET optionCheck = (SELECT COUNT(*)
# 	    						FROM ResurrectOption AS R, BetOption AS B
# 	    						WHERE R.OptionID = B.OptionID AND R.CharID = matchingCharID
# 	    							  AND B.BookNo = currentBookNo);

# 	    	IF(optionCheck = 0) THEN
# 	    		SET wereBetsAffected = 0;
# 	    	ELSE 
# 		    	CALL turn_off_bet_availability(newEventType, currentBookNo, updateStatus);

# 		    	IF(updateStatus = 0) THEN
# 		    		SET wereBetsAffected = 1;
# 		    	ELSE
# 		    		SET wereBetsAffected = 0;
# 		    	END IF;
# 		    END IF;

#     		INSERT INTO Event(ParticipantID, EventType, ParticipantName, BookOccurred, ChangedBets)
#     		VALUES(matchingCharID, newEventType, charName, currentBookNo, wereBetsAffected);

# 	    ELSEIF(oldIsAlive != newIsAlive AND newIsAlive = 0) THEN
# 	    	SET newEventType = 'death';

# 	    	SET optionCheck = (SELECT COUNT(*)
# 	    						FROM DeathOption AS D, BetOption AS B
# 	    						WHERE D.OptionID = B.OptionID AND D.CharID = matchingCharID
# 	    							  AND B.BookNo = currentBookNo);

# 	    	IF(optionCheck = 0) THEN
# 	    		SET wereBetsAffected = 0;
# 	    	ELSE 
# 		    	CALL turn_off_bet_availability(newEventType, currentBookNo, updateStatus);

# 		    	IF(updateStatus = 0) THEN
# 		    		SET wereBetsAffected = 1;
# 		    	ELSE
# 		    		SET wereBetsAffected = 0;
# 		    	END IF;
# 		    END IF;

#     		INSERT INTO Event(ParticipantID, EventType, ParticipantName, BookOccurred, ChangedBets)
#     		VALUES(matchingCharID, newEventType, charName, currentBookNo, wereBetsAffected);

# 	    	SET newEventID = LAST_INSERT_ID();
# 	    ELSE
# 	    	SET wereBetsAffected = 0;
# 	    END IF;


# 	    /* If bets were resolved, then we need to ensure that those bets know which
# 	    event resolved them. So, run through and update bet's field that indicates which
# 	    event resolved them, if needed. */
# 	    IF(wereBetsAffected = 1 and newEventType = 'death') THEN
# 	    	UPDATE Bet
# 	    	SET ResolvingEventID = newEventID
# 	    	WHERE OptionID IN (SELECT B.OptionID
# 	    						FROM BetOption AS B
# 	    						WHERE B.BetType = newEventType AND B.BookNo = currentBookNo);

# 			IF(newEventType = 'death') THEN
# 		    	UPDATE Bet
# 		    	SET Status = 'win'
# 		    	WHERE OptionID IN (SELECT D.OptionID
# 		    						FROM DeathOption AS D, Event AS E
# 		    						WHERE ResolvingEventID = E.EventID 
# 		    							  AND D.CharID = E.ParticipantID);

# 		    	UPDATE Bet
# 		    	SET Status = 'loss'
# 		    	WHERE OptionID IN (SELECT D.OptionID
# 		    						FROM DeathOption AS D, Event AS E
# 		    						WHERE ResolvingEventID = E.EventID 
# 		    							  AND D.CharID != E.ParticipantID);
# 		    ELSEIF(newEventType = 'resurrect') THEN
# 		    	UPDATE Bet
# 		    	SET Status = 'win'
# 		    	WHERE OptionID IN (SELECT R.OptionID
# 		    						FROM ResurrectOption AS R, Event AS E
# 		    						WHERE ResolvingEventID = E.EventID 
# 		    							  AND R.CharID = E.ParticipantID);

# 		    	UPDATE Bet
# 		    	SET Status = 'loss'
# 		    	WHERE OptionID IN (SELECT R.OptionID
# 		    						FROM ResurrectOption AS R, Event AS E
# 		    						WHERE ResolvingEventID = E.EventID 
# 		    							  AND R.CharID != E.ParticipantID);
# 		    END IF;
# 		END IF;

# 		SET output = 0;
# 	END")
# end

# def create_update_house(client)
# 	client.query("DROP procedure IF EXISTS update_house")
# 	client.query("CREATE PROCEDURE update_house(
# 	    IN inputHouseName VARCHAR(80),
# 	    IN newWonThrone SMALLINT,
# 	   	IN currentBookNo INT,
# 	    OUT output INT)

# 	ThisProc:BEGIN
# 		DECLARE matchingHouseID INT;
# 		DECLARE throneWinnersCount INT;
# 		DECLARE oldWonThrone SMALLINT;
# 		DECLARE optionCheck INT;
# 		DECLARE checkOption INT;
# 		DECLARE updateStatus INT;
# 		DECLARE wereBetsAffected INT;
# 		DECLARE newEventID INT;

# 		SET matchingHouseID = (SELECT HouseID
# 								FROM House
# 								WHERE HouseName = inputHouseName);

# 		SET throneWinnersCount = (SELECT COUNT(*)
# 									FROM House
# 									Where WonThrone = 1);

# 		SET oldWonThrone = (SELECT WonThrone
# 								FROM House
# 								WHERE HouseID = matchingHouseID);
# 		/* Validate input */

# 		IF(newWonThrone != 0 AND newWonThrone != 1) THEN
# 			SET newWonThrone = oldWonThrone;
# 		END IF;

# 		IF(throneWinnersCount > 0 AND newWonThrone = 1 AND oldWonThrone != newWonThrone) THEN
# 			SET output = -1;
# 		 	LEAVE ThisProc;
# 		END IF;

# 		IF(oldWonThrone = 0 AND newWonThrone= 1 AND currentBookNo = -1) THEN
# 			SET output = -2;
# 			LEAVE ThisProc;
# 		END IF;


# 		/* Perform update */

# 		UPDATE House
# 		SET WonThrone = newWonThrone
# 		WHERE HouseID = matchingHouseID;

# 	    IF(oldWonThrone != newWonThrone AND newWonThrone = 1) THEN
# 	    	SET optionCheck = (SELECT COUNT(*)
# 	    						FROM ThroneOption AS T, BetOption AS B
# 	    						WHERE T.OptionID = B.OptionID 
# 	    							  AND T.HouseID = matchingHouseID
# 	    							  AND B.BookNo = currentBookNo);

# 	    	IF(optionCheck = 0) THEN
# 	    		SET wereBetsAffected = 0;
# 	    	ELSE 
# 		    	CALL turn_off_bet_availability('throne', currentBookNo, updateStatus);

# 		    	IF(updateStatus = 0) THEN
# 		    		SET wereBetsAffected = 1;
# 		    	ELSE
# 		    		SET wereBetsAffected = 0;
# 		    	END IF;
# 		    END IF;

# 	    	INSERT INTO Event(ParticipantID, EventType, ParticipantName, BookOccurred, ChangedBets)
# 	    	VALUES(matchingHouseID, 'throne', inputHouseName, currentBookNo, wereBetsAffected);
	   
# 	    	SET newEventID = LAST_INSERT_ID();
# 	    END IF;

# 	    /* If bets were affected, then we need to ensure that those bets know which
# 	    event affected them. So, run through and update field that indicates which
# 	    event affected them if needed. */
# 	    IF(wereBetsAffected = 1) THEN
# 	    	UPDATE Bet
# 	    	SET ResolvingEventID = newEventID
# 	    	WHERE OptionID IN (SELECT OptionID
# 	    						FROM BetOption
# 	    						WHERE BetType = 'throne' AND BookNo = currentBookNo);
# 	    END IF;

# 		SET output = 0;
# 	END")
# end

# def create_update_bet_results(client)
# 	client.query("DROP procedure IF EXISTS update_bet_results")
# 	client.query("CREATE PROCEDURE update_bet_results(
# 	    IN removedEventID INT,
# 	    IN newResolvingEventID INT,
# 	    IN currentEventType VARCHAR(20),
# 	    IN currentBookNo INT,
# 	    OUT output INT)

# 	ThisProc:BEGIN

# 		UPDATE Bet
# 		SET ResolvingEventID = newResolvingEventID
# 		WHERE ResolvingEventID = removedEventID;

# 		IF(currentEventType = 'throne') THEN
# 			UPDATE Bet
# 	    	SET Status = 'win'
# 	    	WHERE OptionID IN (SELECT T.OptionID
# 	    						FROM ThroneOption AS T, Event AS E
# 	    						WHERE ResolvingEventID = E.EventID 
# 	    							  AND T.CharID = E.ParticipantID);

# 	    	UPDATE Bet
# 	    	SET Status = 'loss'
# 	    	WHERE OptionID IN (SELECT T.OptionID
# 	    						FROM ThroneOption AS T, Event AS E
# 	    						WHERE ResolvingEventID = E.EventID 
# 	    							  AND T.CharID != E.ParticipantID);
# 		ELSEIF(currentEventType = 'death') THEN
# 			UPDATE Bet
# 	    	SET Status = 'win'
# 	    	WHERE OptionID IN (SELECT D.OptionID
# 	    						FROM DeathOption AS D, Event AS E
# 	    						WHERE ResolvingEventID = E.EventID 
# 	    							  AND D.CharID = E.ParticipantID);

# 			UPDATE Bet
# 	    	SET Status = 'loss'
# 	    	WHERE OptionID IN (SELECT D.OptionID
# 	    						FROM DeathOption AS D, Event AS E
# 	    						WHERE ResolvingEventID = E.EventID 
# 	    							  AND D.CharID != E.ParticipantID);
# 		ELSE
# 			UPDATE Bet
# 	    	SET Status = 'win'
# 	    	WHERE OptionID IN (SELECT R.OptionID
# 	    						FROM ResurrectOption AS R, Event AS E
# 	    						WHERE ResolvingEventID = E.EventID 
# 	    							  AND R.CharID = E.ParticipantID);

# 			UPDATE Bet
# 	    	SET Status = 'loss'
# 	    	WHERE OptionID IN (SELECT R.OptionID
# 	    						FROM ResurrectOption AS R, Event AS E
# 	    						WHERE ResolvingEventID = E.EventID 
# 	    							  AND R.CharID != E.ParticipantID);
# 		END IF;

# 		SET output = 0;
# 	END")
# end

# def create_delete_event(client)
# 	client.query("DROP procedure IF EXISTS delete_event")
# 	client.query("CREATE PROCEDURE delete_event(
# 	    IN removeEventID INT,
# 	    OUT output INT)

# 	ThisProc:BEGIN
# 		DECLARE eventCount INT;
# 		DECLARE wereBetsAffected INT;
# 		DECLARE currentEventType VARCHAR(20);
# 		DECLARE bookNo INT;
# 		DECLARE foreignID INT;
# 		DECLARE eventToModify INT;
# 		DECLARE doBetsNeedUpdate INT;
# 		DECLARE eventStatus INT;
# 		DECLARE updateStatus INT;

# 		SET eventCount = (SELECT COUNT(*)
# 							FROM Event
# 							Where EventID = removeEventID);

# 		IF(eventCount = 0) THEN
# 			SET output = -1;
# 		 	LEAVE ThisProc;
# 		END IF;

# 		SET wereBetsAffected = (SELECT ChangedBets
# 									FROM Event
# 									WHERE EventID = removeEventID);

# 		SET currentEventType = (SELECT EventType
# 									FROM Event
# 									WHERE EventID = removeEventID);

# 		SET bookNo = (SELECT BookOccurred
# 						FROM Event
# 						WHERE EventID = removeEventID);

# 		SET foreignID = (SELECT ParticipantID
# 							FROM Event
# 							WHERE EventID = removeEventID);

# 		DELETE FROM Event
# 		WHERE EventID = removeEventID;

# 		IF(currentEventType = 'throne') THEN
# 			UPDATE House
# 			SET WonThrone = 0
# 			WHERE HouseID = foreignID;

# 			SET eventToModify =	(SELECT MIN(E.EventID)
# 									FROM ThroneOption AS T, BetOption AS B, Event AS E
# 									WHERE T.OptionID = B.OptionID AND T.HouseID = E.ParticipantID
# 										  AND E.EventType = 'throne' AND E.BookOccurred = bookNo);
# 		ELSEIF(currentEventType = 'death') THEN
# 			UPDATE Person
# 			SET IsAlive = 1
# 			WHERE CharID = foreignID;

# 			SET eventToModify =	(SELECT MIN(E.EventID)
# 									FROM DeathOption AS D, BetOption AS B, Event AS E
# 									WHERE D.OptionID = B.OptionID AND D.CharID = E.ParticipantID
# 										  AND E.EventType = 'death' AND E.BookOccurred = bookNo);
# 		ELSE
# 			UPDATE Person
# 			SET IsAlive = 0
# 			WHERE CharID = foreignID;

# 			SET eventToModify =	(SELECT MIN(E.EventID)
# 									FROM ResurrectOption AS R, BetOption AS B, Event AS E
# 									WHERE R.OptionID = B.OptionID AND R.CharID = E.ParticipantID
# 										  AND E.EventType = 'resurrect' AND E.BookOccurred = bookNo);
# 		END IF;


# 		/* 
# 		Removed event caused some bets to be resolved, but no other event will leave these
# 		bets resolved. So, make bets unresolved (available) again and update status of 
# 		associated bets.
# 		*/
# 		IF(wereBetsAffected = 1 AND eventToModify IS NULL) THEN
# 			CALL turn_on_bet_availability(currentEventType, bookNo, eventStatus);

# 			UPDATE Bet
# 			SET ResolvingEventID = NULL,
# 				Status = 'pending'
# 			WHERE ResolvingEventID = removeEventID;

# 		ELSEIF(wereBetsAffected = 1 AND eventToModify IS NOT NULL) THEN
# 		/* Removed event caused some bets to be resolved, but now another event will resolve
# 		these bets instead. Leave bets resolved, but update the event and associated bets
# 		to reflect the change. */
# 			UPDATE Event
# 			SET ChangedBets = 1
# 			WHERE EventID = eventToModify;

# 			CALL update_bet_results(removeEventID, eventToModify, currentEventType, 
# 			bookNo, eventStatus);
# 		END IF;

# 		IF(eventStatus < 0) THEN
# 			SET output = -3;
# 			LEAVE ThisProc;
# 		END IF;

# 		SET output = 0;
# 	END")
# end

def create_stored_procedures(client)
	client.query("USE testBase")

	# create_insert_bet_option(client)
	# create_turn_off_bet_availability(client)
	# create_turn_on_bet_availability(client)
	# create_update_bet_results(client)
	# create_update_person(client)
	# create_update_house(client)
	# create_delete_event(client)
	create_log_and_update_person(client)
	create_log_and_update_house(client)
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
	populate_tables(client, people, stats, battles)
else # How do this considering populate dumps it in special way
	client.query("USE #{databaseName}")
	# add_more_data(client, people, stats, battles)
end

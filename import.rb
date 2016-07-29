require 'csv'
require 'Mysql2'
require 'set'
require 'optparse'

mode = nil
files = []
OptionParser.new do |opts|
	opts.on("-c", "--create [CREATE]", "CREATE database from scratch") do |val|
	  mode = "create"
	end

    opts.on("-a", "--add [ADD]", "ADD to existing data") do |val|
    	mode = "add"
    end

    opts.on("--file FILE", "File to add to database") do |val|
    	files << val
    end
end.parse(ARGV)
raise "You must specify whether to 'create' database (-c) or 'add' to database (-a)" if mode.nil?


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
					HouseID INT AUTO_INCREMENT PRIMARY KEY,
					HouseName VARCHAR(80) NOT NULL UNIQUE,
					WonThrone SMALLINT NOT NULL,
					IsOption SMALLINT NOT NULL DEFAULT 0,
					Odds DECIMAL(10, 3),
					CONSTRAINT house_valid_won_throne CHECK(WonThrone = 0 OR WonThrone = 1),
					CONSTRAINT house_valid_option CHECK(IsOption = 0 OR IsOption = 1))")

	client.query("CREATE TABLE IF NOT EXISTS Person (
					CharID INT AUTO_INCREMENT PRIMARY KEY, 
					Name varchar(80) NOT NULL UNIQUE,
					IsAlive SMALLINT NOT NULL,
					HouseID INT, 
					Gender INT NOT NULL, 
					Title varchar(60), 
					DeathProbability DECIMAL(10, 3) NOT NULL,
					Popularity DECIMAL(10, 6) NOT NULL,
					BookOfDeath SMALLINT NOT NULL,
					IsOption INT NOT NULL DEFAULT 0,
					Odds DECIMAL(10, 3) NOT NULL DEFAULT 0,
					FOREIGN KEY(HouseID) REFERENCES House(HouseID),
					CONSTRAINT person_valid_is_alive CHECK(IsAlive = 0 OR IsAlive = 1),
					CONSTRAINT person_valid_gender CHECK(Gender = 0 OR Gender = 1),
					CONSTRAINT perosn_valid_death_prob CHECK(DeathProbability <= 1),
					CONSTRAINT person_valid_popularity CHECK(Popularity <= 1),
					CONSTRAINT person_valid_option CHECK(IsOption = 0 OR IsOption = 1))")

	client.query("CREATE TABLE IF NOT EXISTS Battle (
					BattleID INT AUTO_INCREMENT PRIMARY KEY, 
					BattleName VARCHAR(80) NOT NULL, 
					City VARCHAR(60), 
					Year INT,
					CONSTRAINT battle_valid_year CHECK(Year > 296))")

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
					ParticipantName VARCHAR(80) NOT NULL,
					BookOccurred SMALLINT NOT NULL)")

	client.query("CREATE TABLE IF NOT EXISTS Bet (
					BetID INT AUTO_INCREMENT PRIMARY KEY,
					OptionName VARCHAR(80) NOT NULL,
					BetType VARCHAR(80) NOT NULL,
					BookNo SMALLINT NOT NULL, 
					UserEmail VARCHAR(100) NOT NULL,
					BetAmount DECIMAL(10, 2) NOT NULL,
					CONSTRAINT bet_min_amt CHECK(BetAmount > 1.00))")

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

			START TRANSACTION;

			SET matchingCharID = (SELECT CharID
									FROM Person
									Where Name = nameToChange);

			SET oldIsAlive = (SELECT IsAlive
								FROM Person
								WHERE CharID = matchingCharID);

			/* Validate input. */

			IF(matchingCharID IS NULL) THEN
				SET output = -1;
			 	ROLLBACK;
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
		    	COMMIT;
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
		    	COMMIT;
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

		    INSERT INTO Event(Description, ParticipantName, BookOccurred)
		    VALUES(newEventDescription, nameToChange, currentBookNo);

		    SET output = 0;

		    COMMIT;
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

			START TRANSACTION;

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
		    	COMMIT;
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
		    	COMMIT;
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

		    INSERT INTO Event(Description, ParticipantName, BookOccurred)
		    VALUES(newEventDescription, inputHouseName, currentBookNo);

		    SET output = 0;

		    COMMIT;
		END")
end

def create_stored_procedures(client)
	create_log_and_update_person(client)
	create_log_and_update_house(client)
end

def create_bet_insert_trigger(client)
	client.query("DROP TRIGGER IF EXISTS check_bet_insert_valid_name_and_id")
	client.query("CREATE TRIGGER check_bet_insert_valid_name_and_id
					BEFORE INSERT 
					ON Bet FOR EACH ROW
				  BEGIN
				  	DECLARE matchingCharCount INT;
				  	DECLARE matchingHouseCount INT;

				  	SET matchingCharCount = (SELECT COUNT(*)
				  								FROM Person
				  								WHERE Name = NEW.OptionName);

				  	SET matchingHouseCount = (SELECT COUNT(*)
				  								FROM House
				  								WHERE HouseName = NEW.OptionName);

				  	IF((matchingCharCount != 1 && matchingHouseCount != 1) 
				  		OR (matchingCharCount > 0 AND matchingHouseCount > 0)) THEN
				  		SET NEW.OptionName = NULL;
				  	END IF;
				  END")
end

def create_bet_update_trigger(client)
	client.query("DROP TRIGGER IF EXISTS check_bet_update_valid_name_and_id")
	client.query("CREATE TRIGGER check_bet_update_valid_name_and_id
					BEFORE UPDATE
					ON Bet FOR EACH ROW
				  BEGIN
				  	DECLARE matchingCharCount INT;
				  	DECLARE matchingHouseCount INT;

				  	SET matchingCharCount = (SELECT COUNT(*)
				  								FROM Person
				  								WHERE Name = NEW.OptionName);

				  	SET matchingHouseCount = (SELECT COUNT(*)
				  								FROM House
				  								WHERE HouseName = NEW.OptionName);

				  	IF((matchingCharCount != 1 && matchingHouseCount != 1) 
				  		OR (matchingCharCount > 0 AND matchingHouseCount > 0)) THEN
				  		SET NEW.OptionName = NULL;
				  	END IF;
				  END")
end

def create_event_insert_trigger(client)
	client.query("DROP TRIGGER IF EXISTS check_event_insert_valid_name_and_id")
	client.query("CREATE TRIGGER check_event_insert_valid_name_and_id
					BEFORE INSERT
					ON Event FOR EACH ROW
				  BEGIN
				  	DECLARE matchingCharCount INT;
				  	DECLARE matchingHouseCount INT;

				  	SET matchingCharCount = (SELECT COUNT(*)
				  								FROM Person
				  								WHERE Name = NEW.ParticipantName);

				  	SET matchingHouseCount = (SELECT COUNT(*)
				  								FROM House
				  								WHERE HouseName = NEW.ParticipantName);

				  	IF((matchingCharCount != 1 && matchingHouseCount != 1) 
				  		OR (matchingCharCount > 0 AND matchingHouseCount > 0)) THEN
				  		SET NEW.ParticipantName = NULL;
				  	END IF;
				  END")
end

def create_event_update_trigger(client)
	client.query("DROP TRIGGER IF EXISTS check_event_update_valid_name_and_id")
	client.query("CREATE TRIGGER check_event_update_valid_name_and_id
					BEFORE UPDATE
					ON Event FOR EACH ROW
				  BEGIN
				  	DECLARE matchingCharCount INT;
				  	DECLARE matchingHouseCount INT;

				  	SET matchingCharCount = (SELECT COUNT(*)
				  								FROM Person
				  								WHERE Name = NEW.ParticipantName);

				  	SET matchingHouseCount = (SELECT COUNT(*)
				  								FROM House
				  								WHERE HouseName = NEW.ParticipantName);

				  	IF((matchingCharCount != 1 && matchingHouseCount != 1) 
				  		OR (matchingCharCount > 0 AND matchingHouseCount > 0)) THEN
				  		SET NEW.ParticipantName = NULL;
				  	END IF;
				  END")
end

def create_triggers(client)
	create_bet_insert_trigger(client)
	create_bet_update_trigger(client)
	create_event_insert_trigger(client)
	create_event_update_trigger(client)
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

def create_indexes(client)
	client.query("CREATE INDEX bet_foreign_name ON Bet(OptionName)")
	client.query("CREATE INDEX event_foreign_name ON Event(ParticipantName)")
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

		currentName = houseNamesArray[i]
		if currentName != "None"
			currentName = remove_bad_char(currentName)

			client.query("INSERT INTO House(HouseName, WonThrone)
				          VALUE('#{currentName}', 0)")

			result = client.query("SELECT LAST_INSERT_ID()")
			result.each do |val|
				houseIdMapping.merge!({currentName => val[0]})
				break
			end
		end
	end


	# Insert values into character and death tables
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

			houseName = remove_bad_char(person[1])

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

				client.query("INSERT INTO Person(IsAlive, HouseID, Name, 
		        	Gender, Title, DeathProbability, Popularity, BookOfDeath) 
			        VALUES(#{personIsAlive}, #{houseId}, '#{name}',
			         #{gender}, '#{title}', #{probability}, #{popularity}, #{bookOfDeath})")

			else
				client.query("INSERT INTO Person(IsAlive, Name, 
		        	Gender, Title, DeathProbability, Popularity, BookOfDeath) 
			        VALUES(#{personIsAlive}, '#{name}',
			         #{gender}, '#{title}', #{probability}, #{popularity}, #{bookOfDeath})")
			end

		end
	end

	# Insert values into Battle table
	battles.each do |battle|
		# Insert battle into Battle
		battleName = battle[0]
		battleName = remove_bad_char(battleName)

		location = battle[22]
		location = remove_bad_char(location)

		year = battle[1].to_i

		client.query("INSERT INTO Battle (BattleName, City, Year)
			          VALUE('#{battleName}' ,'#{location}',#{year})")


		# Insert participating houses into CombatLog
		result = client.query("SELECT LAST_INSERT_ID()")
		lastBattleID = 0
		result.each do |val|
			lastBattleID = val[0]
			break
		end
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
	        	VALUES(#{houseId}, #{lastBattleID}, '#{result}')")
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

				client.query("INSERT INTO CombatLog()
	        	VALUES(#{houseId}, #{lastBattleID}, '#{result}')")
			end
		end
	end


	# Populate options with our initial options
	populate_option_tables(client);
	# Leave bet tables empty, as no bets have been made yet
end

def add_to_tables(client, people, stats, battles)
	if(people != nil)
		personNamesHash = Hash.new()

		lastIndex = stats.size-1
		for i in 1..lastIndex
			personNamesHash.merge!({stats[i][5] => i})
		end

		# Insert values into character and death tables
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

				houseName = remove_bad_char(person[1])

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
					houseId = 0
					result = client.query("SELECT HouseID
												FROM House
												WHERE HouseName = '%s'" % houseName)

					result.each do |val|
						houseId = val[0]
						break
					end

					client.query("INSERT INTO Person(IsAlive, HouseID, Name, 
			        	Gender, Title, DeathProbability, Popularity, BookOfDeath) 
				        VALUES(#{personIsAlive}, #{houseId}, '#{name}',
				         #{gender}, '#{title}', #{probability}, #{popularity}, #{bookOfDeath})")

				else
					client.query("INSERT INTO Person(IsAlive, Name, 
			        	Gender, Title, DeathProbability, Popularity, BookOfDeath) 
				        VALUES(#{personIsAlive}, '#{name}',
				         #{gender}, '#{title}', #{probability}, #{popularity}, #{bookOfDeath})")
				end

			end
		end
	end



	if(battles != nil)
		# Insert values into Battle table
		battles.each do |battle|
			# Insert battle into Battle
			battleName = battle[0]
			battleName = remove_bad_char(battleName)

			location = battle[22]
			location = remove_bad_char(location)

			year = battle[1].to_i

			client.query("INSERT INTO Battle (BattleName, City, Year)
				          VALUE('#{battleName}' ,'#{location}',#{year})")


			# Insert participating houses into CombatLog
			result = client.query("SELECT LAST_INSERT_ID()")
			lastBattleID = 0
			result.each do |val|
				lastBattleID = val[0]
				break
			end
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
				if(!defenders.include?(name)) 
					houseId = 0
					returned = client.query("SELECT HouseID
												FROM House
												WHERE HouseName = '%s'" % houseName)

					returned.each do |val|
						houseId = val[0]
						break
					end

					result = ""
					if (battle[13] == "win")
						result = "win"
					elsif (battle[13] == "loss")
						result = "loss"
					else
						result = "inconclusive"
					end
					client.query("INSERT INTO CombatLog()
		        	VALUES(#{houseId}, #{lastBattleID}, '#{result}')")
				end
			end


			# Obtain the necessary data to insert each defender into the CombatLog table.
			defenders.each do |name|
				if(!attackers.include?(name))
					houseId = 0
					result = client.query("SELECT HouseID
												FROM House
												WHERE HouseName = '%s'" % houseName)

					result.each do |val|
						houseId = val[0]
						break
					end

					result = ""
					if (battle[13] == "win")
						result = "loss"
					elsif (battle[13] == "loss")
						result = "win"
					else
						result = "inconclusive"
					end

					client.query("INSERT INTO CombatLog()
		        	VALUES(#{houseId}, #{lastBattleID}, '#{result}')")
				end
			end
		end
	end
end

# Connect to client
Mysql2::Client.default_query_options.merge!(:as => :array)
client = Mysql2::Client.new(:host => "192.168.91.2",:username => "testuser", :password => "mysqltest")

# Create the database and associated tables/views
databaseName = "testBase"
people = nil
stats = nil
battles = nil
if mode == "create" 
	# Parse the data tables
	people = CSV.read('character.csv')
	stats = CSV.read('prediction.csv')
	battles = CSV.read('battles.csv')

	# Create database
	create_database(client, databaseName)
	client.query("USE #{databaseName}")
	drop_tables(client)
	create_tables_and_views(client)
	create_stored_procedures(client)
	create_triggers(client)
	create_indexes(client)
	# Populate the database
	populate_tables(client, people, stats, battles)
else
	files.each do |file|
		begin
			currentFile = CSV.read(file)
			if currentFile[0][1] == "Allegiances"
				people = currentFile
			elsif currentFile[0][0] == "S.No"
				stats = currentFile
			elsif currentFile[0][1] == "Year"
				battles = currentFile
			else
				puts "#{file} does not match an expected format and will not be used."
			end
		rescue Exception => e
			puts e.message
		end
	end

	if battles.nil? && people.nil? && stats.nil?
		puts "Provide some file to import data from."
	elsif ( !people.nil? && stats.nil?) || (people.nil? && !stats.nil?)
		puts "Provide two files to insert people."
	else
		client.query("USE #{databaseName}")
		add_to_tables(client, people, stats, battles)
	end

end

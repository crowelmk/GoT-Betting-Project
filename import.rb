require 'csv'
require 'Mysql2'
require 'set'
require 'optparse'


mode= nil
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
	client.query("DROP TABLE IF EXISTS DeathBet")
	client.query("DROP TABLE IF EXISTS RFDBet")
	client.query("DROP TABLE IF EXISTS HouseBet")
	client.query("DROP TABLE IF EXISTS Bet")
	client.query("DROP TABLE IF EXISTS CombatLog")
	client.query("DROP TABLE IF EXISTS Death")
	client.query("DROP TABLE IF EXISTS Person")
	client.query("DROP TABLE IF EXISTS House")
	client.query("DROP TABLE IF EXISTS Battle")
end

def create_tables_and_views(client)
	# Tables

	# Note: House has multiple derived attributes that are expressed in a view on House involving both
	# the combat log and the Person and Death tables.
	client.query("CREATE TABLE IF NOT EXISTS House (
					HouseID INT PRIMARY KEY, 
					HouseName VARCHAR(80) NOT NULL UNIQUE)")

	client.query("CREATE TABLE IF NOT EXISTS Person (
					CharID INT PRIMARY KEY, 
					IsAlive SMALLINT NOT NULL,
					HouseID INT NOT NULL, 
					Name varchar(80) NOT NULL, 
					Gender INT NOT NULL, 
					Title varchar(60), 
					IntroBookNo INT, 
					FOREIGN KEY(HouseID) REFERENCES House(HouseID))")

	client.query("CREATE TABLE IF NOT EXISTS Death (
					DeathID INT, 
					CharID INT, 
					DeathYear INT NOT NULL, 
					DeathBookNo INT, 
					DeathChapterNo INT, 
					PRIMARY KEY(DeathID, CharID), 
					FOREIGN KEY(CharID) REFERENCES Person(CharID),
					CHECK(DeathYear > 296))")

	client.query("CREATE TABLE IF NOT EXISTS Battle (
					BattleID INT PRIMARY KEY, 
					BattleName VARCHAR(80) NOT NULL, 
					City VARCHAR(60), 
					Year INT NOT NULL,
					CHECK(Year > 296))")

	client.query("CREATE TABLE IF NOT EXISTS CombatLog (
					HouseID INT NOT NULL, 
					BattleID INT NOT NULL, 
					Result VARCHAR(60), 
					PRIMARY KEY(HouseID, BattleID),
					FOREIGN KEY(HouseID) REFERENCES House(HouseID), 
					FOREIGN KEY(BattleID) REFERENCES Battle(BattleID))")

	client.query("CREATE TABLE IF NOT EXISTS Bet (
					BetID INT AUTO_INCREMENT PRIMARY KEY,
					BetType VARCHAR(60) NOT NULL,
					UserEmail VARCHAR(100) NOT NULL,
					BetAmount DECIMAL(10, 2) NOT NULL,
					Result VARCHAR(30),
					CHECK(CashBet > 1.00))")

	client.query("CREATE TABLE IF NOT EXISTS DeathBet (
					BetID INT NOT NULL, 
					CharID INT NOT NULL, 
					FOREIGN KEY(BetID) REFERENCES Bet(BetID),
					FOREIGN KEY(CharID) REFERENCES Person(CharID),
					PRIMARY KEY(BetID))")

	# RFD = Resurrect from death
	client.query("CREATE TABLE IF NOT EXISTS RFDBet (
					BetID INT NOT NULL, 
					CharID INT NOT NULL, 
					FOREIGN KEY(BetID) REFERENCES Bet(BetID),
					FOREIGN KEY(CharID) REFERENCES Death(CharID),
					PRIMARY KEY(BetID))")

	client.query("CREATE TABLE IF NOT EXISTS HouseBet (
					BetID INT NOT NULL, 
					HouseID INT NOT NULL, 
					FOREIGN KEY(BetID) REFERENCES Bet(BetID),
					FOREIGN KEY(HouseID) REFERENCES House(HouseID),
					PRIMARY KEY(BetID))")

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
							FROM House AS H, Death as D, Person AS P
							WHERE H.HouseID = P.HouseID AND P.CharID = D.CharID
							GROUP BY HouseID")

	client.query("CREATE OR REPLACE VIEW HouseBattleStats (
					HouseID, HouseName, NumBattlesWon)
					AS SELECT H.HouseID, H.HouseName, COUNT(BattleID)
							FROM House AS H, CombatLog L
							WHERE H.HouseID = L.HouseID AND result = 'win'
							GROUP BY HouseID")
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

		client.query("INSERT INTO House(HouseID, HouseName)
			          VALUE(#{houseId}, '#{currentName}')")
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

			if(person[2] != nil) # person is dead, record their death
				# In our imported data, no person has died twice. However, since characters
				# are able to be resurrected, it is worth having a deathId that tracks which
				# death a character's entry in the DEATH table refers to.
				deathId = 1

				deathYear = person[2].to_i

				deathBookNo = person[3].to_i

				deathBookChap = person[4].to_i

				client.query("INSERT INTO Death(DeathID, CharID, DeathYear, DeathBookNo, DeathChapterNo)
	       	 				  VALUES(#{deathId}, #{currentIdValue}, #{deathYear}, #{deathBookNo}, #{deathBookChap})")
			end
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

	# Leave bet tables empty, as no bets have been made yet
end

def create_stored_procedures(client)
	client.query("USE testBase")
	client.query(
	"DROP procedure IF EXISTS `insert_bet`;
DELIMITER $$
USE `testBase`$$
CREATE PROCEDURE `insert_bet`(
	    IN betType varchar(30),
	    IN email varchar(100),
	    IN bet decimal(10, 2),
	    IN optionID int,
	    OUT output int)
	BEGIN
		DECLARE currentBetID INT;

		INSERT INTO Bet (BetType, UserEmail, BetAmount, Result) 
	    VALUES (betType, email, bet, 'pending');
	    
	    SET currentBetID = LAST_INSERT_ID();
	    
		IF(betType = 'house') THEN
			INSERT INTO HouseBet
	        VALUES (currentBetID, optionID);
		ELSEIF(betType = 'death') THEN
			INSERT INTO DeathBet
	        VALUES (currentBetID, optionID);
		ELSEIF(betType = 'resurrect') THEN
			INSERT INTO RFDBet
	        VALUES(currentBetID, optionID);
		ELSE
			SET output = -1;
	    END IF;
	    
		SET output = 0;
	END$$

DELIMITER ;")
end

# Parse the data tables
people = CSV.read('character.csv')
stats = CSV.read('prediction.csv')
battles = CSV.read('battles.csv')

# Connect to client
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

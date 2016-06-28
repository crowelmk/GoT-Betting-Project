require 'csv'
require 'Mysql2'
require 'set'

def remove_bad_char(input_string)
	if(input_string != nil)
		return input_string.gsub("'", "''")
	end
end

people = CSV.read('character.csv')
stats = CSV.read('prediction.csv')
battles = CSV.read('battles.csv')

client = Mysql2::Client.new(:host => "137.112.244.248",:username => "testuser", :password => "mysqltest", :database => "testBase")

client.query("DROP TABLE MurderBet")
client.query("DROP TABLE RFDBet")
client.query("DROP TABLE HouseBet")
client.query("DROP TABLE CombatLog")
client.query("DROP TABLE Death")
client.query("DROP TABLE Person")
client.query("DROP TABLE House")
client.query("DROP TABLE Battle")

personNamesHash = Hash.new()
last = stats.size-1
for i in 1..last
	personNamesHash.merge!({stats[i][5] => i})
end

houseNames = Set.new()
houseNamesAndAliveCount = Hash.new()
houseNamesAndDeathCount = Hash.new()

# Grab data for creating house table
people.each do |person|
	name = person[0]
	if personNamesHash.has_key?(name)

        # Add the current character's house to the set of houses. If this house (or one
        # with a matching name) has already been added, then this operation will not 
        # do anything.
		house_name = person[1]

		# Given our source's formatting, there may be two names such as "Stark" and
		# "House Stark." To avoid this issue, we will each name by " " and, if the
		# first part is "House", remove the first part.
		house_name_split = house_name.split(" ")
		if house_name_split[0] == "House"
			house_name = house_name_split[1]
		end
		houseNames.add(house_name)

		if(person[2] != nil) # person is dead, record their death
			# In our imported data, no person has died twice. However, since characters
			# are able to be resurrected, it is worth having a death_id that tracks which
			# death a character's entry in the DEATH table refers to.
		
			if(houseNamesAndDeathCount.has_key?(house_name))
				current_death_toll = houseNamesAndDeathCount.fetch(house_name) + 1
				houseNamesAndDeathCount.merge!({house_name => current_death_toll})
			else 
				houseNamesAndDeathCount.merge!({house_name => 1})
			end
		else # person is alive
			if(houseNamesAndAliveCount.has_key?(house_name))
				current_alive_count = houseNamesAndAliveCount.fetch(house_name) + 1
				houseNamesAndAliveCount.merge!({house_name => current_alive_count})
			else 
				houseNamesAndAliveCount.merge!({house_name => 1})
			end
		end
	end
end


client.query("CREATE TABLE House (HouseID INT PRIMARY KEY, HouseName VARCHAR(80), NumAlive INT, NumDead INT)")

houseNamesArray = houseNames.to_a
houseIdMapping = Hash.new();
lastIndex = houseNamesArray.length - 1
for i in 0..lastIndex
	house_id = i + 1

	current_name = houseNamesArray[i]
	if current_name == nil
		current_name = "Unaffiliated"
	end
	houseIdMapping.merge!({current_name => house_id})
	house_alive_count = 0
	if houseNamesAndAliveCount.has_key?(current_name)
		house_alive_count = houseNamesAndAliveCount.fetch(current_name)
	end

	house_death_count = 0
	if houseNamesAndDeathCount.has_key?(current_name)
		house_death_count = houseNamesAndDeathCount.fetch(current_name)
	end

	current_name = remove_bad_char(current_name)

	client.query("INSERT INTO House
		          VALUE(#{house_id}, '#{current_name}', #{house_alive_count},#{house_death_count})")
end


client.query("CREATE TABLE Person (CharID INT, HouseID INT, Name varchar(50), Gender INT, Title varchar(60), IntroBookNo INT, PRIMARY KEY(CharID), FOREIGN KEY(HouseID) REFERENCES House(HouseID))")

client.query("CREATE TABLE Death (DeathID INT, CharID INT, DeathYear INT, DeathBookNo INT, DeathChapterNo INT, PRIMARY KEY(DeathID, CharID), FOREIGN KEY(CharID) REFERENCES Person(CharID))")

# Insert values into character and death tables
cnt = 1
people.each do |person|
	name = person[0]
	if personNamesHash.has_key?(name)
		statrow = personNamesHash.fetch(name)
		name = remove_bad_char(name)

		gender = stats[statrow][7].to_i

		title = stats[statrow][6]
		title = remove_bad_char(title)

		book_index = 8
		while(person[book_index].to_i == 0) 
			book_index = book_index + 1
		end
		intro_book_no = book_index - 7

		house_name_split = person[1].split(" ")
		if house_name_split[0] == "House"
			house_name = house_name_split[1]
		end
		house_name = person[1]
		house_name_split = house_name.split(" ")
		if house_name_split[0] == "House"
			house_name = house_name_split[1]
		end
		house_id = houseIdMapping.fetch(house_name)
        client.query("INSERT INTO Person(CharID, HouseID, Name, Gender, Title, IntroBookNo) 
        VALUES(#{cnt}, #{house_id}, '#{name}', #{gender}, '#{title}', #{intro_book_no})")

		if(person[2] != nil) # person is dead, record their death
			# In our imported data, no person has died twice. However, since characters
			# are able to be resurrected, it is worth having a death_id that tracks which
			# death a character's entry in the DEATH table refers to.
			death_id = 1

			death_year = person[2].to_i

			death_book_no = person[3].to_i

			death_book_chap = person[4].to_i

			if(houseNamesAndDeathCount.has_key?(house_name))
				current_death_toll = houseNamesAndDeathCount.fetch(house_name) + 1
				houseNamesAndDeathCount.merge!({house_name => current_death_toll})
			else 
				houseNamesAndDeathCount.merge!({house_name => 1})
			end

			client.query("INSERT INTO Death
       	 				  VALUES(#{death_id}, #{cnt}, #{death_year}, #{death_book_no}, #{death_book_chap})")
		end
		cnt = cnt + 1
	end
end



result = client.query("CREATE TABLE Battle (BattleID INT PRIMARY KEY, BattleName varchar(80), City varchar(60), Year INT)")
cnt = 1
battles.each do |battle|
	battle_name = battle[0]
	battle_name = remove_bad_char(battle_name)

	location = battle[22]
	location = remove_bad_char(location)

	year = battle[1].to_i

	client.query("INSERT INTO Battle
		          VALUE(#{cnt}, '#{battle_name}' ,'#{location}',#{year})")
	cnt = cnt + 1
end

client.query("CREATE TABLE MurderBet (MurderBetID INT, CharID INT, UserEmail varchar(60), CashBet numeric(15,2), PRIMARY KEY (MurderBetID), FOREIGN KEY(CharID) REFERENCES Person(CharID))")

client.query("CREATE TABLE RFDBet (RFDBetID INT, CharID INT, DeathID INT, UserEmail varchar(60), CashBet numeric(15,2), PRIMARY KEY (RFDBetID), FOREIGN KEY(CharID, DeathID) REFERENCES Death(CharID, DeathID))")

client.query("CREATE TABLE HouseBet (HouseBetID INT, HouseID INT, UserEmail varchar(60), CashBet numeric(15,2), PRIMARY KEY (HouseBetID), FOREIGN KEY(HouseID) REFERENCES House(HouseID))")

client.query("CREATE TABLE CombatLog (HouseID INT, BattleID INT, Victory bool, FOREIGN KEY(HouseID) REFERENCES House(HouseID), FOREIGN KEY(BattleID) REFERENCES Battle(BattleID))")







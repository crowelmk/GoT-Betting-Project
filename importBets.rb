require 'csv'
require 'Mysql2'

def remove_bad_char(input_string)
	if(input_string != nil)
		return input_string.gsub("'", "''")
	end
end

people = CSV.read('character.csv')
stats = CSV.read('prediction.csv')
battles = CSV.read('battles.csv')

hostIP = "192.168.241.128"
dbUser = "root"
dbKey = "Pravstra6"
dbName = "Test"

hash = Hash.new()
last = stats.size-1
for i in 1..last
	hash.merge!({stats[i][5] => i})
end

client = Mysql2::Client.new(:host => hostIP,:username => dbUser, :password => dbKey, :database => dbName)

client.query("CREATE TABLE MurderBet (MurderBetID int, OptionNo int, UserEmail varchar(60), CashBet numeric(15,2), PRIMARY KEY (MurderBetID))")

client.query("CREATE TABLE RFDBet (RFDBetID int, OptionNo int, UserEmail varchar(60), CashBet numeric(15,2), PRIMARY KEY (RFDBetID))")

client.query("CREATE TABLE HouseBet (HouseBetID int, OptionNo int, UserEmail varchar(60), CashBet numeric(15,2), PRIMARY KEY (HouseBetID))")

#CREATE TABLE House (HouseID int, PRIMARY KEY(HouseID))
#CREATE TABLE Battle (BattleID int, PRIMARY KEY(BattleID))

client.query("CREATE TABLE CombatLog (HouseID int, BattleID int, Victory bool, FOREIGN KEY(HouseID) REFERENCES House(HouseID), FOREIGN KEY(BattleID) REFERENCES Battle(BattleID))")
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

hash = Hash.new()
last = stats.size-1
for i in 1..last
	hash.merge!({stats[i][5] => i})
end

client = Mysql2::Client.new(:host => "137.112.244.248",:username => "testuser", :password => "mysqltest", :database => "testBase")
client.query("DROP TABLE Person")
client.query("CREATE TABLE Person (CharID int, Name varchar(50), Gender INT, Title varchar(60), IntroBookNo INT, PRIMARY KEY(CharID))")  

cnt = 1
people.each do |person|
	name = person[0]
	if hash.has_key?(name)
		statrow = hash.fetch(name)
		name = remove_bad_char(name)
		gender = stats[statrow][7].to_i
		title = stats[statrow][6]
		title = remove_bad_char(title)
		book_index = 8
		while(person[book_index].to_i == 0) 
			book_index = book_index + 1
		end
		intro_book_no = book_index - 7
        client.query("INSERT INTO Person(CharID, Name, Gender, Title, IntroBookNo) 
        VALUES(#{cnt}, '#{name}', #{gender}, '#{title}', #{intro_book_no})")
		cnt = cnt+1
	end
end


client.query("DROP TABLE Battle")
result = client.query("CREATE TABLE Battle (BattleID int, BattleName varchar(80), City varchar(60), Year int, PRIMARY KEY(BattleID))")
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

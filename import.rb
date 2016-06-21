require 'csv'

people = CSV.read('character.csv')
stats = CSV.read('prediction.csv')

# people.each do |person|
# 	person.each do |detail|
# 		print "#{detail} "
#     end
#     puts ''
# end

# stats.each do |stat|
# 	stat.each do |detail|
# 		print "#{detail} "
#     end
#     puts ''
# end

hash = Hash.new()
last = stats.size-1
for i in 1..last
	hash.merge!({stats[i][5] => i})
	puts "#{hash.fetch(stats[i][5])}"
end




puts "cnt: #{cnt}"
client = Mysql2::Client.new(:host => "137.112.244.248",:username => "testuser", :password => "mysqltest", :database => "testBase")
result = client.query("CREATE TABLE Character (CharID int, Name varchar(50), Gender int, Popularity double, Title varchar(20), IntroBookNo int, PRIMARY KEY(CharID))")

cnt = 1
people.each do |person|
	name = person[0]
	if hash.has_key?(name)
		statrow = hash.fetch(name)
        client.query("INSERT INTO Character
        	          VALUE(#{cnt}, #{name}, #{stats[statrow][6]}, #{stats[statrow][31]}, #{stats[statrow][1]}, #{person[5]})")
		cnt = cnt+1
	end
end

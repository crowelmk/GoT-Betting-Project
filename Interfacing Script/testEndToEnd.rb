#!/usr/bin/ruby
require 'mysql2'

#connect to mysql database

client = Mysql2::Client.new(:host => "137.112.244.248",:username => "testuser", :password => "mysqltest", :database => "testBase");
result = client.query("SELECT * FROM infoToGet")
result.each do |val|
	puts "#{val['id']}, #{val['name']}"
end
# begin
#  # connect to the MySQL server
#  dbh = DBI.connect("DBI:Mysql:testBase:127.0.0.1", 
#                     "testuser", "mysqltest")
#  # get server version string and display it
#  row = dbh.select_one("SELECT VERSION()")
#  puts "Server version: " + row[0]
# rescue DBI::DatabaseError => e
#  puts "An error occurred"
#  puts "Error code:    #{e.err}"
#  puts "Error message: #{e.errstr}"
# ensure
#  # disconnect from server
#  dbh.disconnect if dbh
# end
# 
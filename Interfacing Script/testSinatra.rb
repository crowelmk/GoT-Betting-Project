#!/usr/bin/ruby
require 'sinatra'
require 'mysql2'
require 'erb'

template_path = "test.html.erb"
template_file = File.read(template_path)

# Interpret erb file
html_doc = ERB.new(template_file).result(binding)

get '/' do
	html_doc
end

get '/about' do
  'A little about me.'
end
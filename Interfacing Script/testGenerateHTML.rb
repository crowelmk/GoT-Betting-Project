#!/usr/bin/ruby
require 'mysql2'
require 'erb'

template_path = "test.html.erb"
template_file = File.read(template_path)

# Interpret erb file
html_doc = ERB.new(template_file).result(binding)
puts html_doc
#!/usr/bin/env ruby

require 'curses'
require 'socket'
require_relative 'lib/game_engine'
require_relative 'lib/player'
require_relative 'lib/networking'

# Main game entry point
if __FILE__ == $PROGRAM_NAME
  puts "Welcome to Subprime Showdown!"

  # Use the Heroku server URL by default, or localhost for testing
  # Set the LOCAL_SERVER environment variable to use localhost
       server_ip = "localhost"
      port = 8080
  #  if ENV['LOCAL_SERVER']
  #  server_ip = "localhost"
  #  port = 8080
  #else
  #  server_ip = "subprimeshowdown-70e905ab4841.herokuapp.com"
  #  port = 443  # Use HTTPS port for Heroku
  #end

  puts "Connecting to server at #{server_ip}:#{port}..."

  game = GameEngine.new(server_ip: server_ip, port: port.to_i)
  game.start
end

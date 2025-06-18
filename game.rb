#!/usr/bin/env ruby

require 'curses'
require 'socket'
require_relative 'lib/game_engine'
require_relative 'lib/player'
require_relative 'lib/networking'

# Main game entry point
if __FILE__ == $PROGRAM_NAME
  puts "Welcome to Subprime Showdown!"
  puts "Enter the server's IP address (or leave blank for localhost):"
  server_ip = gets.chomp
  server_ip = "localhost" if server_ip.empty?

  puts "Enter the server port (default: 8080):"
  port = gets.chomp
  port = 8080 if port.empty?

  puts "Connecting to server at #{server_ip}:#{port}..."

  game = GameEngine.new(server_ip: server_ip, port: port.to_i)
  game.start
end

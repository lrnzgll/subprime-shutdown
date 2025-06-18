#!/usr/bin/env ruby

require 'curses'
require 'socket'
require_relative 'lib/game_engine'
require_relative 'lib/player'
require_relative 'lib/networking'

# Main game entry point
if __FILE__ == $PROGRAM_NAME
  puts "Welcome to Subprime Showdown!"
  puts "1. Host a game"
  puts "2. Join a game"
  choice = gets.chomp.to_i

  case choice
  when 1
    puts "Starting server..."
    server_ip = `curl -4 ifconfig.me`.strip || "localhost"
    port = 8080
    puts "Your game is hosted at #{server_ip}:#{port}"
    puts "NOTE: If connecting from different networks, you need to set up port forwarding on your router for port #{port}"
    puts "Waiting for another player to join..."

    game = GameEngine.new(is_host: true, server_ip: server_ip, port: port)
    game.start
  when 2
    puts "Enter the host's IP address:"
    host_ip = gets.chomp
    puts "Enter the port (default: 8080):"
    port = gets.chomp
    port = 8080 if port.empty?

    game = GameEngine.new(is_host: false, server_ip: host_ip, port: port.to_i)
    game.start
  else
    puts "Invalid choice. Exiting."
  end
end

#!/usr/bin/env ruby

require 'curses'
require 'socket'
require_relative 'lib/game_engine'
require_relative 'lib/player'
require_relative 'lib/networking'

# Main game entry point
if __FILE__ == $PROGRAM_NAME
  puts "Welcome to Subprime Showdown!"

  # Use TCP connection to localhost
  server_ip = "5.tcp.eu.ngrok.io"
  port = 13933

  puts "Connecting to server at #{server_ip}:#{port}..."

  game = GameEngine.new(server_ip: server_ip, port: port.to_i)
  game.start
end

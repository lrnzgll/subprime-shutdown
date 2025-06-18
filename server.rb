#!/usr/bin/env ruby

require 'socket'
require 'json'
require_relative 'lib/player'

class GameServer
  def initialize(port = ENV['PORT'] ? ENV['PORT'].to_i : 8080)
    @port = port
    @clients = []
    @players = []
    @running = true
    puts "Initializing server with port: #{@port}"
  end

  def start
    puts "Starting Subprime Showdown server on port #{@port}..."
    begin
      @server = TCPServer.new(@port)
      puts "Server socket successfully created and bound to port #{@port}"
    rescue => e
      puts "ERROR: Failed to create server socket: #{e.message}"
      puts "ERROR: #{e.backtrace.join("\n")}"
      return
    end

    puts "Waiting for players to connect..."

    # Wait for exactly 2 players to connect
    while @clients.size < 2
      client = @server.accept
      client_id = @clients.size
      @clients << client

      # Create a player for this client
      player = Player.new("Player #{client_id + 1}", client_id == 0 ? 10 : 70, client_id == 0 ? 10 : 14)
      @players << player

      puts "Player #{client_id + 1} connected! (#{@clients.size}/2)"

      # Send initial player data to the client
      send_to_client(client, {
        client_id: client_id,
        player: player.to_hash,
        game_ready: @clients.size == 2
      })
    end

    puts "Game starting with 2 players!"

    # Notify both clients that the game is ready to start
    @clients.each_with_index do |client, id|
      send_to_client(client, {
        game_ready: true,
        client_id: id,
        players: @players.map(&:to_hash)
      })
    end

    # Start the main server loop
    server_loop
  end

  private

  def server_loop
    puts "Starting main server loop with #{@clients.size} connected clients"

    # Create a thread for each client to handle incoming messages
    threads = @clients.map.with_index do |client, id|
      Thread.new do
        puts "Started thread for client #{id}"
        while @running
          begin
            # Read data from client
            data = client.gets.chomp
            if data && !data.empty?
              puts "Received data from client #{id}"
              handle_client_message(id, JSON.parse(data, symbolize_names: true))
            end
          rescue => e
            puts "Error reading from client #{id}: #{e.message}"
            puts "Error backtrace: #{e.backtrace.join("\n")}"
            handle_client_disconnect(id)
            break
          end
        end
        puts "Thread for client #{id} terminated"
      end
    end

    puts "All client threads started, waiting for them to complete"
    # Wait for all threads to complete
    threads.each(&:join)
    puts "All client threads completed, server loop ending"
  end

  def handle_client_message(client_id, message)
    # Update the player state based on the message
    if message[:player]
      @players[client_id].update_from_hash(message[:player])

      # Broadcast updated game state to all clients
      broadcast_game_state
    end
  end

  def handle_client_disconnect(client_id)
    puts "Player #{client_id + 1} disconnected."
    @running = false

    # Notify remaining client
    other_id = (client_id + 1) % 2
    if @clients[other_id] && !@clients[other_id].closed?
      send_to_client(@clients[other_id], { game_over: true, reason: "Other player disconnected" })
    end

    # Close all connections
    @clients.each do |client|
      client.close unless client.closed?
    end

    @server.close unless @server.closed?
  end

  def broadcast_game_state
    game_state = {
      players: @players.map(&:to_hash)
    }

    @clients.each do |client|
      send_to_client(client, game_state)
    end
  end

  def send_to_client(client, data)
    begin
      client.puts(JSON.generate(data))
    rescue => e
      puts "Error sending to client: #{e.message}"
    end
  end
end

# Start the server if this file is executed directly
if __FILE__ == $PROGRAM_NAME
  server = GameServer.new
  server.start
end

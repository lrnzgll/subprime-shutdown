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

    # Main server loop that continues accepting new games
    while true
      # Reset state for a new game
      reset_server_state

      puts "Waiting for players to connect..."

      # Wait for exactly 2 players to connect
      while @clients.size < 2 && @running
        begin
          # Set a timeout for accept to allow checking @running
          ready = IO.select([@server], nil, nil, 1)
          if ready && ready[0].include?(@server)
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
        rescue => e
          puts "Error accepting client: #{e.message}"
          sleep 1  # Avoid tight loop if there's an error
        end
      end

      # If we have 2 players and the server is still running
      if @clients.size == 2 && @running
        puts "Game starting with 2 players!"

        # Notify both clients that the game is ready to start
        @clients.each_with_index do |client, id|
          send_to_client(client, {
            game_ready: true,
            client_id: id,
            players: @players.map(&:to_hash)
          })
        end

        # Start the game server loop
        game_server_loop
      end
    end
  end

  private

  def game_server_loop
    puts "Starting main server loop with #{@clients.size} connected clients"

    # Create a thread for each client to handle incoming messages
    threads = @clients.map.with_index do |client, id|
      Thread.new do
        puts "Started thread for client #{id}"
        while @running
          begin
            # Read data from client
            raw_data = client.gets
            if raw_data.nil?
              puts "Client #{id} disconnected (received nil)"
              handle_client_disconnect(id)
              break
            end

            data = raw_data.chomp
            if !data.empty?
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

    # Mark this client as disconnected
    @clients[client_id] = nil

    # Notify remaining client
    other_id = (client_id + 1) % 2
    if @clients[other_id] && !@clients[other_id].closed?
      send_to_client(@clients[other_id], { game_over: true, reason: "Other player disconnected" })
      # Close the remaining client connection gracefully
      @clients[other_id].close unless @clients[other_id].closed?
      @clients[other_id] = nil
    end

    # Check if all clients are disconnected
    if @clients.compact.empty?
      puts "All clients disconnected, resetting server state"
      @running = false
      reset_server_state
    end
  end

  def reset_server_state
    # Reset server state to accept new connections
    @clients = []
    @players = []
    @running = true

    # Don't close the server socket, keep it open for new connections
    puts "Server reset and ready for new connections"
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

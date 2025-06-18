#!/usr/bin/env ruby

require 'socket'
require 'json'
require 'securerandom'
require_relative 'lib/player'

# GameRoom class to manage individual game instances
class GameRoom
  attr_reader :id, :invite_code, :host_id, :players, :player_data, :state

  def initialize(id, host_id, host_client)
    @id = id
    @invite_code = generate_invite_code
    @host_id = host_id
    @players = [host_id]
    @clients = { host_id => host_client }
    @player_data = {}
    @state = "waiting"
    @running = true
    @threads = []
  end

  def add_player(client_id, client, player_name)
    @players << client_id
    @clients[client_id] = client

    # Create a player for this client with appropriate starting position
    position = @players.size - 1
    player = Player.new(player_name || "Player #{client_id}", position == 0 ? 10 : 70, position == 0 ? 10 : 14)
    @player_data[client_id] = player.to_hash

    # If we have 2 players, we can start the game
    if @players.size >= 2
      @state = "ready"
    end

    return true
  end

  def start_game
    return false unless @state == "ready"

    @state = "in_progress"

    # Notify all players that the game is starting
    notify_all_players({
      action: "game_started",
      status: "success",
      data: {
        room_id: @id,
        players: player_data_array
      }
    })

    # Start game loop for this room
    start_game_loop

    return true
  end

  def start_game_loop
    puts "Starting game loop for room #{@id} with #{@players.size} players"

    # Create a thread for each client to handle incoming messages
    @threads = @players.map do |client_id|
      client = @clients[client_id]

      Thread.new do
        puts "Started thread for client #{client_id} in room #{@id}"
        while @running
          begin
            # Check if client is still connected
            if client.nil? || (client.respond_to?(:closed?) && client.closed?)
              puts "Client #{client_id} in room #{@id} is nil or closed"
              handle_client_disconnect(client_id)
              break
            end

            # Read data from client with timeout to avoid blocking indefinitely
            ready = IO.select([client], nil, nil, 1)
            if ready && ready[0].include?(client)
              raw_data = client.gets
              if raw_data.nil?
                puts "Client #{client_id} in room #{@id} disconnected (received nil)"
                handle_client_disconnect(client_id)
                break
              end

              data = raw_data.chomp
              if !data.empty?
                puts "Received data from client #{client_id} in room #{@id}"
                handle_client_message(client_id, JSON.parse(data, symbolize_names: true))
              end
            end
          rescue => e
            puts "Error reading from client #{client_id} in room #{@id}: #{e.message}"
            puts "Error backtrace: #{e.backtrace.join("\n")}"
            handle_client_disconnect(client_id)
            break
          end
        end
        puts "Thread for client #{client_id} in room #{@id} terminated"
      end
    end

    # Wait for all threads to complete in a separate thread
    Thread.new do
      @threads.each(&:join)
      puts "All client threads for room #{@id} completed, game loop ending"
      @state = "completed"
    end
  end

  def handle_client_message(client_id, message)
    # Handle game-specific messages
    if message[:action] == "game_action" && message[:data]
      # Update the player state based on the message
      if message[:data][:player]
        if @player_data[client_id]
          # Update player data
          @player_data[client_id].merge!(message[:data][:player])

          # Broadcast updated game state to all clients
          broadcast_game_state
        end
      end
    end
  end

  def handle_client_disconnect(client_id)
    puts "Player #{client_id} disconnected from room #{@id}."

    # Mark this client as disconnected
    @clients[client_id] = nil

    # Notify remaining players
    @players.each do |player_id|
      next if player_id == client_id || @clients[player_id].nil?

      begin
        if !@clients[player_id].closed?
          send_to_client(@clients[player_id], {
            action: "player_disconnected",
            status: "success",
            data: {
              player_id: client_id,
              reason: "Player disconnected"
            }
          })
        end
      rescue => e
        puts "Error notifying player #{player_id} about disconnect: #{e.message}"
      end
    end

    # Check if all clients are disconnected
    if @clients.values.compact.empty?
      puts "All clients disconnected from room #{@id}, ending game"
      @running = false
      @state = "completed"
    end
  end

  def broadcast_game_state
    game_state = {
      action: "game_update",
      status: "success",
      data: {
        room_id: @id,
        players: player_data_array
      }
    }

    notify_all_players(game_state)
  end

  def notify_all_players(data)
    @players.each do |player_id|
      client = @clients[player_id]
      if client && !(client.respond_to?(:closed?) && client.closed?)
        send_to_client(client, data)
      end
    end
  end

  def send_to_client(client, data)
    return if client.nil?

    begin
      # Check if client is still connected
      if client.respond_to?(:closed?) && client.closed?
        puts "Cannot send to closed client"
        return
      end

      # Send data to client
      client.puts(JSON.generate(data))
    rescue => e
      puts "Error sending to client: #{e.message}"
    end
  end

  def player_data_array
    result = []
    @players.each do |player_id|
      if @player_data[player_id]
        player_info = @player_data[player_id].clone
        player_info[:id] = player_id
        result << player_info
      end
    end
    result
  end

  private

  def generate_invite_code
    # Generate a short, readable code (e.g., "ABC123")
    letters = ('A'..'Z').to_a
    numbers = ('0'..'9').to_a
    (letters.sample(3) + numbers.sample(3)).join
  end
end

class GameServer
  def initialize(port = ENV['PORT'] ? ENV['PORT'].to_i : 8080)
    @port = port
    @clients = {}  # client_id => socket
    @rooms = {}    # room_id => GameRoom
    @client_rooms = {}  # client_id => room_id
    @next_client_id = 0
    puts "Initializing server with port: #{@port}"
  end

  def start
    puts "Starting Subprime Showdown server on port #{@port}..."
    begin
      @server = TCPServer.new(@port)
      puts "TCP server successfully created and bound to port #{@port}"
    rescue => e
      puts "ERROR: Failed to create server socket: #{e.message}"
      puts "ERROR: #{e.backtrace.join("\n")}"
      return
    end

    # Start a thread to clean up completed rooms
    start_cleanup_thread

    puts "Waiting for client connections..."

    # Main server loop
    while true
      begin
        # Accept new client connections
        ready = IO.select([@server], nil, nil, 1)
        if ready && ready[0].include?(@server)
          begin
            client = @server.accept
            client_id = @next_client_id
            @next_client_id += 1
            @clients[client_id] = client

            puts "Client #{client_id} connected!"

            # Start a thread to handle this client's lobby messages
            Thread.new do
              handle_lobby_client(client_id, client)
            end
          rescue => e
            puts "Error accepting client connection: #{e.message}"
          end
        end
      rescue => e
        puts "Error in main server loop: #{e.message}"
        sleep 1  # Avoid tight loop if there's an error
      end
    end
  end

  private

  def start_cleanup_thread
    Thread.new do
      while true
        # Find and remove completed rooms
        @rooms.each do |room_id, room|
          if room.state == "completed"
            puts "Removing completed room #{room_id}"
            @rooms.delete(room_id)
          end
        end
        sleep 10  # Check every 10 seconds
      end
    end
  end

  def handle_lobby_client(client_id, client)
    puts "Handling lobby messages for client #{client_id}"

    # Send initial welcome message
    send_to_client(client, {
      action: "welcome",
      status: "success",
      data: {
        client_id: client_id,
        message: "Welcome to Subprime Showdown! You can create a new game or join an existing one."
      }
    })

    while true
      begin
        # Check if client is still connected
        if client.nil? || (client.respond_to?(:closed?) && client.closed?)
          puts "Lobby client #{client_id} is nil or closed"
          handle_lobby_disconnect(client_id)
          break
        end

        # Read data from client with timeout
        ready = IO.select([client], nil, nil, 1)
        if ready && ready[0].include?(client)
          raw_data = client.gets
          if raw_data.nil?
            puts "Lobby client #{client_id} disconnected (received nil)"
            handle_lobby_disconnect(client_id)
            break
          end

          data = raw_data.chomp
          if !data.empty?
            puts "Received lobby data from client #{client_id}: #{data}"
            message = JSON.parse(data, symbolize_names: true)
            handle_lobby_message(client_id, client, message)

            # If client joined a room, stop handling lobby messages
            if @client_rooms[client_id]
              puts "Client #{client_id} joined room #{@client_rooms[client_id]}, stopping lobby handler"
              break
            end
          end
        end
      rescue => e
        puts "Error handling lobby client #{client_id}: #{e.message}"
        puts "Error backtrace: #{e.backtrace.join("\n")}"
        handle_lobby_disconnect(client_id)
        break
      end
    end

    puts "Lobby handler for client #{client_id} terminated"
  end

  def handle_lobby_message(client_id, client, message)
    case message[:action]
    when "create_game"
      create_game(client_id, client, message[:data])
    when "join_game"
      join_game(client_id, client, message[:data])
    else
      send_to_client(client, {
        action: message[:action],
        status: "error",
        error: "Unknown action"
      })
    end
  end

  def create_game(client_id, client, data)
    # Create a new game room
    room_id = "room_#{SecureRandom.hex(6)}"
    room = GameRoom.new(room_id, client_id, client)

    # Add the player to the room
    player_name = data && data[:player_name] ? data[:player_name] : "Player #{client_id}"
    room.add_player(client_id, client, player_name)

    # Store the room
    @rooms[room_id] = room
    @client_rooms[client_id] = room_id

    puts "Created new game room #{room_id} with invite code #{room.invite_code}"

    # Notify client of successful game creation
    send_to_client(client, {
      action: "game_created",
      status: "success",
      data: {
        room_id: room_id,
        invite_code: room.invite_code,
        host_id: client_id
      }
    })
  end

  def join_game(client_id, client, data)
    return unless data && data[:invite_code]

    invite_code = data[:invite_code].to_s.upcase  # Ensure invite code is uppercase
    puts "Client #{client_id} trying to join with invite code: #{invite_code}"
    puts "Available rooms: #{@rooms.values.map { |r| "#{r.id} (#{r.invite_code}, state: #{r.state})" }.join(', ')}"

    room = @rooms.values.find { |r| r.invite_code == invite_code }

    if room
      puts "Found room #{room.id} with state: #{room.state}"
    else
      puts "No room found with invite code: #{invite_code}"
    end

    if room && (room.state == "waiting" || room.state == "ready")
      # Add player to the room
      player_name = data[:player_name] ? data[:player_name] : "Player #{client_id}"
      if room.add_player(client_id, client, player_name)
        @client_rooms[client_id] = room.id

        puts "Client #{client_id} joined room #{room.id} with state: #{room.state}"

        # Notify all players in the room
        room.notify_all_players({
          action: "player_joined",
          status: "success",
          data: {
            room_id: room.id,
            players: room.player_data_array
          }
        })

        # Start the game if we have enough players
        if room.state == "ready"
          room.start_game
        end
      else
        send_to_client(client, {
          action: "join_game",
          status: "error",
          error: "Failed to join game"
        })
      end
    else
      # Notify client of failure
      error_message = if !room
                        "Invalid invite code - no game found with this code"
                      else
                        "Game is already in progress or completed (state: #{room.state})"
                      end

      puts "Join failed: #{error_message}"

      send_to_client(client, {
        action: "join_game",
        status: "error",
        error: error_message
      })
    end
  end

  def handle_lobby_disconnect(client_id)
    puts "Lobby client #{client_id} disconnected."
    @clients.delete(client_id)
  end

  def send_to_client(client, data)
    return if client.nil?

    begin
      # Check if client is still connected
      if client.respond_to?(:closed?) && client.closed?
        puts "Cannot send to closed client"
        return
      end

      # Send data to client
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

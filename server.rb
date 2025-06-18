#!/usr/bin/env ruby

require 'socket'
require 'json'
require 'openssl'
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
      tcp_server = TCPServer.new(@port)

      if @port == 443
        # Set up SSL/TLS for secure connections on port 443
        puts "Setting up SSL/TLS for secure connections on port 443"
        ssl_context = OpenSSL::SSL::SSLContext.new

        # In production, you would use proper certificate files
        # For development/testing, we'll generate a self-signed certificate
        ssl_context.cert = OpenSSL::X509::Certificate.new
        ssl_context.key = OpenSSL::PKey::RSA.new(2048)
        ssl_context.cert.version = 2
        ssl_context.cert.serial = 1
        name = OpenSSL::X509::Name.new([['CN', 'localhost']])
        ssl_context.cert.subject = name
        ssl_context.cert.issuer = name
        ssl_context.cert.not_before = Time.now
        ssl_context.cert.not_after = Time.now + 365 * 24 * 60 * 60 # 1 year validity
        ssl_context.cert.public_key = ssl_context.key.public_key
        ssl_context.cert.sign(ssl_context.key, OpenSSL::Digest::SHA256.new)

        @server = OpenSSL::SSL::SSLServer.new(tcp_server, ssl_context)
        puts "SSL/TLS server successfully created and bound to port #{@port}"
      else
        @server = tcp_server
        puts "TCP server successfully created and bound to port #{@port}"
      end
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
            begin
              client = @server.accept
              client_id = @clients.size
              @clients << client
            rescue => e
              puts "Error accepting client connection: #{e.message}"
              next
            end

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
            # Check if client is still connected
            if client.nil? || (client.respond_to?(:closed?) && client.closed?)
              puts "Client #{id} is nil or closed"
              handle_client_disconnect(id)
              break
            end

            # Read data from client with timeout to avoid blocking indefinitely
            ready = IO.select([client], nil, nil, 1)
            if ready && ready[0].include?(client)
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
    if @clients[other_id]
      begin
        if !@clients[other_id].closed?
          send_to_client(@clients[other_id], { game_over: true, reason: "Other player disconnected" })
          # Close the remaining client connection gracefully
          @clients[other_id].close unless @clients[other_id].closed?
        end
      rescue => e
        puts "Error handling other client: #{e.message}"
      end
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

    @clients.each_with_index do |client, id|
      if client && !(client.respond_to?(:closed?) && client.closed?)
        send_to_client(client, game_state)
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
end

# Start the server if this file is executed directly
if __FILE__ == $PROGRAM_NAME
  server = GameServer.new
  server.start
end

require 'socket'
require 'json'

# Networking class to handle communication with the game server
class Networking
  attr_reader :client_id, :connected, :game_ready, :players

  def initialize(server_ip, port)
    @server_ip = server_ip
    @port = port
    @connected = false
    @client_id = nil
    @game_ready = false
    @players = []
  end

  def connect
    # Connect to the game server
    begin
      puts "Connecting to server at #{@server_ip}:#{@port}..."
      @socket = TCPSocket.new(@server_ip, @port)
      @connected = true

      # Get initial data from server
      initial_data = receive_data
      if initial_data
        @client_id = initial_data[:client_id]
        @game_ready = initial_data[:game_ready]

        if initial_data[:players]
          @players = initial_data[:players]
        elsif initial_data[:player]
          # If server sends single player data, add it to players array
          # Make sure the array is large enough
          @players = Array.new(2) if @players.empty?
          @players[@client_id] = initial_data[:player]
        end

        puts "Connected to server! You are Player #{@client_id + 1}"
        return true
      end

      return false
    rescue => e
      puts "Error connecting to server: #{e.message}"
      return false
    end
  end

  def send_data(data)
    return false unless @connected

    begin
      # Convert data to JSON and send it
      json_data = JSON.generate(data)
      @socket.puts(json_data)
      return true
    rescue => e
      puts "Error sending data: #{e.message}"
      @connected = false
      return false
    end
  end

  def receive_data
    return nil unless @connected

    begin
      # Set socket to non-blocking mode
      ready = IO.select([@socket], nil, nil, 0.01)

      if ready && ready[0].include?(@socket)
        data = @socket.gets.chomp
        return JSON.parse(data, symbolize_names: true) if data && !data.empty?
      end

      return nil
    rescue => e
      puts "Error receiving data: #{e.message}"
      @connected = false
      return nil
    end
  end

  def close
    @socket.close if @socket && !@socket.closed?
    @connected = false
  end

  # Process server updates and return game state
  def process_updates
    data = receive_data
    if data
      if data[:game_ready]
        @game_ready = true
      end

      if data[:players]
        @players = data[:players]
      end

      if data[:game_over]
        puts "Game over: #{data[:reason]}"
        return false
      end
    end

    return true
  end
end

require 'socket'
require 'json'
require 'openssl'

# Networking class to handle communication with the game server
class Networking
  attr_reader :client_id, :connected, :game_ready, :players, :room_id, :invite_code, :host_id

  def initialize(server_ip, port)
    @server_ip = server_ip
    @port = port
    @connected = false
    @client_id = nil
    @game_ready = false
    @players = []
    @room_id = nil
    @invite_code = nil
    @host_id = nil
    @last_message = nil
  end

  def connect
    # Connect to the game server
    begin
      puts "Connecting to server at #{@server_ip}:#{@port}..."

      if @port == 443
        # Use SSL/TLS for secure connection on port 443
        tcp_socket = TCPSocket.new(@server_ip, @port)
        ssl_context = OpenSSL::SSL::SSLContext.new
        ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE  # For development only
        @socket = OpenSSL::SSL::SSLSocket.new(tcp_socket, ssl_context)
        @socket.sync_close = true
        @socket.connect
        puts "Established secure connection using SSL/TLS"
      else
        # Use regular TCP connection for other ports
        @socket = TCPSocket.new(@server_ip, @port)
      end

      @connected = true

      # Wait for welcome message from server
      welcome_data = wait_for_message("welcome")
      if welcome_data && welcome_data[:status] == "success"
        @client_id = welcome_data[:data][:client_id]
        puts "Connected to server! You are client #{@client_id}"
        puts welcome_data[:data][:message]
        return true
      end

      return false
    rescue => e
      puts "Error connecting to server: #{e.message}"
      return false
    end
  end

  def create_game(player_name)
    return false unless @connected

    # Send create_game request to server
    send_data({
      action: "create_game",
      data: {
        player_name: player_name
      }
    })

    # Wait for game_created response
    response = wait_for_message("game_created")
    if response && response[:status] == "success"
      @room_id = response[:data][:room_id]
      @invite_code = response[:data][:invite_code]
      @host_id = response[:data][:host_id]

      puts "Game created successfully!"
      puts "Room ID: #{@room_id}"
      puts "Invite code: #{@invite_code}"
      puts "You are the host (ID: #{@host_id})"

      return true
    end

    puts "Failed to create game"
    return false
  end

  def join_game(invite_code, player_name)
    return false unless @connected

    # Send join_game request to server
    send_data({
      action: "join_game",
      data: {
        invite_code: invite_code,
        player_name: player_name
      }
    })

    # Wait for player_joined or error response
    response = wait_for_message(["player_joined", "join_game"])
    if response && response[:status] == "success"
      @room_id = response[:data][:room_id]
      @players = response[:data][:players]

      puts "Joined game successfully!"
      puts "Room ID: #{@room_id}"
      puts "Players in room: #{@players.size}"

      return true
    elsif response && response[:status] == "error"
      puts "Failed to join game: #{response[:error]}"
    else
      puts "Failed to join game: No response from server"
    end

    return false
  end

  def wait_for_game_start
    puts "Waiting for game to start..."
    puts "Share the invite code with another player and wait for them to join."
    puts "The game will start automatically when another player joins."
    puts "Waiting for up to 5 minutes..."

    # Wait for game_started message with a longer timeout (5 minutes)
    response = wait_for_message("game_started", 300)
    if response && response[:status] == "success"
      @game_ready = true
      @players = response[:data][:players]

      puts "Game started!"
      puts "Players: #{@players.size}"

      return true
    end

    puts "Timed out waiting for another player to join."
    return false
  end

  def send_game_action(player_data)
    return false unless @connected && @game_ready

    # Send game_action to server
    send_data({
      action: "game_action",
      data: {
        player: player_data
      }
    })

    return true
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

  def wait_for_message(expected_actions, timeout = 10)
    expected_actions = [expected_actions] if expected_actions.is_a?(String)
    start_time = Time.now
    last_status_time = start_time
    status_interval = 30  # Show status message every 30 seconds

    while Time.now - start_time < timeout
      # Show periodic status messages for long waits
      if timeout > 60 && Time.now - last_status_time >= status_interval
        if expected_actions.include?("game_started")
          puts "Still waiting for another player to join... (#{((timeout - (Time.now - start_time)) / 60).to_i} minutes remaining)"
        else
          puts "Still waiting for #{expected_actions.join(' or ')}... (#{((timeout - (Time.now - start_time)) / 60).to_i} minutes remaining)"
        end
        last_status_time = Time.now
      end

      data = receive_data
      if data && expected_actions.include?(data[:action])
        @last_message = data
        return data
      elsif data
        # Store the message for later processing
        @last_message = data

        # If we received a different message, process it
        process_message(data)
      end
      sleep(0.1)
    end

    puts "Timeout waiting for #{expected_actions.join(' or ')} message"
    return nil
  end

  def process_message(data)
    case data[:action]
    when "player_joined"
      if data[:status] == "success"
        new_player = data[:data][:players].last
        puts "\nA new player has joined the game!"
        puts "Player name: #{new_player[:name] || 'Unknown'}"
        puts "Total players: #{data[:data][:players].size}"
        puts "The game will start automatically in a moment...\n"
        @players = data[:data][:players]
      end
    when "player_disconnected"
      if data[:status] == "success"
        puts "\nPlayer #{data[:data][:player_id]} disconnected: #{data[:data][:reason]}\n"
      end
    when "game_update"
      if data[:status] == "success"
        @players = data[:data][:players]
      end
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
      @last_message = data
      process_message(data)

      if data[:action] == "game_update" && data[:status] == "success"
        return true
      end

      if data[:action] == "player_disconnected"
        puts "Game over: Player disconnected"
        return false
      end
    end

    return true
  end
end

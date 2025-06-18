require 'socket'
require 'json'

# Networking class to handle communication between players
class Networking
  def initialize(is_host, server_ip, port)
    @is_host = is_host
    @server_ip = server_ip
    @port = port
    @connected = false
  end

  def connect
    if @is_host
      # Host mode: create a server and wait for a client to connect
      begin
        @server = TCPServer.new(@port)
        puts "Waiting for player to connect on port #{@port}..."
        @socket = @server.accept
        @connected = true
        puts "Player connected!"
        return true
      rescue => e
        puts "Error creating server: #{e.message}"
        return false
      end
    else
      # Client mode: connect to the host
      begin
        puts "Connecting to host at #{@server_ip}:#{@port}..."
        @socket = TCPSocket.new(@server_ip, @port)
        @connected = true
        puts "Connected to host!"
        return true
      rescue => e
        puts "Error connecting to host: #{e.message}"
        return false
      end
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
    @server.close if @is_host && @server && !@server.closed?
    @connected = false
  end
end

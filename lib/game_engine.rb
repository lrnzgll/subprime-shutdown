require 'curses'
require_relative 'player'
require_relative 'networking'

# GameEngine class to handle game loop, rendering, and game state
class GameEngine
  MAP_WIDTH = 80
  MAP_HEIGHT = 24

  # Game objects representation
  WALL = '#'
  BULLET = '*'
  EMPTY = ' '

  def initialize(server_ip:, port:)
    @running = true
    @map = Array.new(MAP_HEIGHT) { Array.new(MAP_WIDTH, EMPTY) }
    @player_id = nil
    @players = []

    # For rate limiting and optimization
    @update_counter = 0
    @player_changed = false
    @last_buffer = nil
    @map_buffer = nil
    @last_update_time = Time.now
    @target_frame_time = 1.0 / 60  # Target 60 FPS

    # Create walls around the map
    create_map

    # Set up networking
    @networking = Networking.new(server_ip, port)

    # Players will be initialized after connecting to the server
    @local_player = nil
    @remote_players = []
  end

  def start
    # Connect to the server first (without initializing curses)
    if @networking.connect
      # Show menu to create or join game
      choice = show_menu

      if choice == 1  # Create new game
        player_name = get_player_name
        if @networking.create_game(player_name)
          puts "Game created! Share this invite code with other players: #{@networking.invite_code}"
          puts "Waiting for players to join..."
          if @networking.wait_for_game_start
            initialize_game
          else
            puts "Failed to start game."
            return
          end
        else
          puts "Failed to create game."
          return
        end
      elsif choice == 2  # Join existing game
        player_name = get_player_name
        invite_code = get_invite_code
        if @networking.join_game(invite_code, player_name)
          puts "Successfully joined game. Waiting for game to start..."
          if @networking.wait_for_game_start
            initialize_game
          else
            puts "Failed to start game."
            return
          end
        else
          puts "Failed to join game."
          return
        end
      else
        puts "Invalid choice."
        return
      end
    else
      puts "Failed to connect to the server."
      return
    end
  end

  def initialize_game
    # Initialize curses
    Curses.init_screen
    Curses.curs_set(0)  # Hide cursor
    Curses.noecho       # Don't echo input
    Curses.stdscr.keypad(true)  # Enable arrow keys
    Curses.timeout = 100  # Non-blocking input with 100ms timeout

    # Find our player in the players list
    @player_id = @networking.client_id
    @players = @networking.players

    # Find our player data
    local_player_data = nil
    @players.each do |player|
      if player[:id] == @player_id
        local_player_data = player
        break
      end
    end

    if !local_player_data
      Curses.close_screen
      puts "Error: Could not find local player data"
      return
    end

    # Initialize local player
    @local_player = Player.new("You", local_player_data[:x], local_player_data[:y])

    # Initialize remote players
    @remote_players = []
    @players.each do |player|
      next if player[:id] == @player_id
      remote_player = Player.new("Player #{player[:id]}", player[:x], player[:y])
      @remote_players << remote_player
    end

    # Pre-render static map elements
    @map_buffer = Array.new(MAP_HEIGHT) { Array.new(MAP_WIDTH, nil) }
    render_static_map

    puts "Game starting! You are Player #{@player_id}"

    game_loop
  end

  # Pre-render the static map elements
  def render_static_map
    @map.each_with_index do |row, y|
      row.each_with_index do |cell, x|
        @map_buffer[y][x] = cell
      end
    end
  end

  # Show menu to create or join game
  def show_menu
    puts "Welcome to Subprime Showdown!"
    puts "1. Create new game"
    puts "2. Join existing game"
    print "Enter your choice (1-2): "
    choice = gets.chomp.to_i
    return choice
  end

  # Get player name from user
  def get_player_name
    print "Enter your name: "
    name = gets.chomp
    return name.empty? ? "Player" : name
  end

  # Get invite code from user
  def get_invite_code
    print "Enter invite code: "
    return gets.chomp.upcase
  end

  private

  def game_loop
    while @running
      frame_start = Time.now

      # Store previous state to detect changes
      prev_x, prev_y, prev_dir = @local_player.x, @local_player.y, @local_player.direction
      prev_bullets_count = @local_player.bullets.size

      # Handle input (may change player state)
      handle_input

      # Check if player state changed
      @player_changed ||= (prev_x != @local_player.x || prev_y != @local_player.y ||
                        prev_dir != @local_player.direction ||
                        prev_bullets_count != @local_player.bullets.size)

      # Update game state
      update_game_state

      # Send updates less frequently or when player state changes
      @update_counter += 1
      if (@player_changed && @update_counter >= 2) || @update_counter >= 5
        @networking.send_game_action(@local_player.to_hash)
        @player_changed = false
        @update_counter = 0
      end

      # Process updates from server (could also be rate-limited)
      if !@networking.process_updates
        @running = false
        break
      end

      # Update remote players from server data
      update_remote_players

      # Render the game
      render

      # Check for game over
      check_game_over

      # Calculate how long to sleep to maintain target frame rate
      elapsed = Time.now - frame_start
      sleep_time = [@target_frame_time - elapsed, 0].max
      sleep(sleep_time) if sleep_time > 0
    end

    # Clean up
    Curses.close_screen
  end

  def update_remote_players
    # Get the latest player data from the server
    server_players = @networking.players

    # Update existing remote players and add new ones
    server_players.each do |player_data|
      next if player_data[:id] == @player_id  # Skip local player

      # Find if we already have this player
      remote_player = @remote_players.find { |p| p.name == "Player #{player_data[:id]}" }

      if remote_player
        # Update existing player
        remote_player.update_from_hash(player_data)
      else
        # Add new player
        new_player = Player.new("Player #{player_data[:id]}", player_data[:x], player_data[:y])
        new_player.update_from_hash(player_data)
        @remote_players << new_player
      end
    end

    # Remove players that are no longer in the game
    @remote_players.reject! do |player|
      player_id = player.name.gsub("Player ", "").to_i
      !server_players.any? { |p| p[:id] == player_id }
    end
  end

  def handle_input
    case Curses.getch
    when Curses::KEY_UP
      @local_player.move(Player::UP, MAP_WIDTH, MAP_HEIGHT)
    when Curses::KEY_RIGHT
      @local_player.move(Player::RIGHT, MAP_WIDTH, MAP_HEIGHT)
    when Curses::KEY_DOWN
      @local_player.move(Player::DOWN, MAP_WIDTH, MAP_HEIGHT)
    when Curses::KEY_LEFT
      @local_player.move(Player::LEFT, MAP_WIDTH, MAP_HEIGHT)
    when ' '  # Spacebar to shoot
      @local_player.shoot
    when 'q', 'Q'
      @running = false
    end
  end

  def update_game_state
    # Update bullets
    @local_player.update_bullets(MAP_WIDTH, MAP_HEIGHT)

    # Check for bullet collisions with players
    check_bullet_collisions
  end

  def check_bullet_collisions
    # Check local player's bullets hitting remote players
    @local_player.bullets.reject! do |bullet|
      hit = false

      @remote_players.each do |remote_player|
        if bullet[:x] == remote_player.x && bullet[:y] == remote_player.y
          remote_player.hit
          @local_player.score += 10
          hit = true
          break
        end
      end

      hit
    end

    # Check remote players' bullets hitting local player
    @remote_players.each do |remote_player|
      remote_player.bullets.reject! do |bullet|
        if bullet[:x] == @local_player.x && bullet[:y] == @local_player.y
          @local_player.hit
          remote_player.score += 10
          true
        else
          false
        end
      end
    end
  end

  def render
    # Create a new buffer based on the static map
    buffer = Marshal.load(Marshal.dump(@map_buffer))

    # Add dynamic elements to buffer

    # Add local player to buffer
    buffer[@local_player.y][@local_player.x] = @local_player.char

    # Add remote players to buffer
    @remote_players.each do |player|
      if player.y >= 0 && player.y < MAP_HEIGHT && player.x >= 0 && player.x < MAP_WIDTH
        buffer[player.y][player.x] = player.char
      end
    end

    # Add bullets to buffer
    [@local_player, *@remote_players].each do |player|
      player.bullets.each do |bullet|
        if bullet[:y] >= 0 && bullet[:y] < MAP_HEIGHT && bullet[:x] >= 0 && bullet[:x] < MAP_WIDTH
          buffer[bullet[:y]][bullet[:x]] = BULLET
        end
      end
    end

    # Only update screen positions that changed
    buffer.each_with_index do |row, y|
      row.each_with_index do |cell, x|
        if @last_buffer.nil? || @last_buffer[y][x] != cell
          Curses.setpos(y, x)
          Curses.addstr(cell.to_s)
        end
      end
    end

    @last_buffer = buffer

    # Render HUD (always update HUD as it may change frequently)
    render_hud

    # Refresh the screen
    Curses.refresh
  end

  def render_hud
    # Display local player health and score
    Curses.setpos(MAP_HEIGHT + 1, 0)
    Curses.addstr("#{@local_player.name}: Health: #{@local_player.health} | Score: #{@local_player.score}")

    # Display remote players health and score
    @remote_players.each_with_index do |player, index|
      Curses.setpos(MAP_HEIGHT + 2 + index, 0)
      Curses.addstr("#{player.name}: Health: #{player.health} | Score: #{player.score}")
    end

    # Display controls
    Curses.setpos(MAP_HEIGHT + 3 + @remote_players.size, 0)
    Curses.addstr("Controls: Arrow keys to move, Space to shoot, Q to quit")
  end

  def check_game_over
    if !@local_player.alive?
      @running = false

      Curses.setpos(MAP_HEIGHT / 2, MAP_WIDTH / 2 - 5)
      Curses.addstr("YOU LOSE!")

      Curses.refresh
      sleep(3)  # Show the game over message for 3 seconds
    elsif @remote_players.all? { |p| !p.alive? }
      @running = false

      Curses.setpos(MAP_HEIGHT / 2, MAP_WIDTH / 2 - 5)
      Curses.addstr("YOU WIN!")

      Curses.refresh
      sleep(3)  # Show the game over message for 3 seconds
    end
  end

  def create_map
    # Create walls around the map
    MAP_HEIGHT.times do |y|
      MAP_WIDTH.times do |x|
        if y == 0 || y == MAP_HEIGHT - 1 || x == 0 || x == MAP_WIDTH - 1
          @map[y][x] = WALL
        end
      end
    end

    # Add some obstacles in the middle
    (MAP_WIDTH / 4).upto(MAP_WIDTH * 3 / 4) do |x|
      @map[MAP_HEIGHT / 3][x] = WALL
      @map[MAP_HEIGHT * 2 / 3][x] = WALL
    end
  end
end

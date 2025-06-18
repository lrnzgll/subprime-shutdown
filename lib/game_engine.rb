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

  def initialize(is_host:, server_ip:, port:)
    @is_host = is_host
    @running = true
    @map = Array.new(MAP_HEIGHT) { Array.new(MAP_WIDTH, EMPTY) }

    # Create walls around the map
    create_map

    # Set up networking
    @networking = Networking.new(is_host, server_ip, port)

    # Initialize players
    player_name = "Player #{@is_host ? '1' : '2'}"
    @local_player = Player.new(player_name, @is_host ? 10 : 70, @is_host ? 10 : 14)
    @remote_player = Player.new("Remote Player", @is_host ? 70 : 10, @is_host ? 14 : 10)
  end

  def start
    # Initialize curses
    Curses.init_screen
    Curses.curs_set(0)  # Hide cursor
    Curses.noecho       # Don't echo input
    Curses.stdscr.keypad(true)  # Enable arrow keys
    Curses.timeout = 100  # Non-blocking input with 100ms timeout

    # Connect to remote player
    if @networking.connect
      game_loop
    else
      Curses.close_screen
      puts "Failed to establish connection."
    end
  end

  private

  def game_loop
    while @running
      # Handle input
      handle_input

      # Update game state
      update_game_state

      # Send local player state to remote player
      @networking.send_data(@local_player.to_hash)

      # Receive remote player state
      remote_data = @networking.receive_data
      @remote_player.update_from_hash(remote_data) if remote_data

      # Render the game
      render

      # Check for game over
      check_game_over

      # Sleep to control game speed
      sleep(0.05)
    end

    # Clean up
    Curses.close_screen
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
    # Check local player's bullets hitting remote player
    @local_player.bullets.reject! do |bullet|
      if bullet[:x] == @remote_player.x && bullet[:y] == @remote_player.y
        @remote_player.hit
        @local_player.score += 10
        true
      else
        false
      end
    end

    # Check remote player's bullets hitting local player
    @remote_player.bullets.reject! do |bullet|
      if bullet[:x] == @local_player.x && bullet[:y] == @local_player.y
        @local_player.hit
        @remote_player.score += 10
        true
      else
        false
      end
    end
  end

  def render
    # Clear the screen
    Curses.clear

    # Render the map
    @map.each_with_index do |row, y|
      row.each_with_index do |cell, x|
        Curses.setpos(y, x)
        Curses.addstr(cell)
      end
    end

    # Render players
    Curses.setpos(@local_player.y, @local_player.x)
    Curses.addstr(@local_player.char)

    Curses.setpos(@remote_player.y, @remote_player.x)
    Curses.addstr(@remote_player.char)

    # Render bullets
    [@local_player, @remote_player].each do |player|
      player.bullets.each do |bullet|
        Curses.setpos(bullet[:y], bullet[:x])
        Curses.addstr(BULLET)
      end
    end

    # Render HUD
    render_hud

    # Refresh the screen
    Curses.refresh
  end

  def render_hud
    # Display player health and score
    Curses.setpos(MAP_HEIGHT + 1, 0)
    Curses.addstr("#{@local_player.name}: Health: #{@local_player.health} | Score: #{@local_player.score}")

    Curses.setpos(MAP_HEIGHT + 2, 0)
    Curses.addstr("#{@remote_player.name}: Health: #{@remote_player.health} | Score: #{@remote_player.score}")

    # Display controls
    Curses.setpos(MAP_HEIGHT + 4, 0)
    Curses.addstr("Controls: Arrow keys to move, Space to shoot, Q to quit")
  end

  def check_game_over
    if !@local_player.alive? || !@remote_player.alive?
      @running = false

      Curses.setpos(MAP_HEIGHT / 2, MAP_WIDTH / 2 - 5)
      if !@local_player.alive?
        Curses.addstr("YOU LOSE!")
      else
        Curses.addstr("YOU WIN!")
      end

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

# Player class to handle player state, movement, and actions
class Player
  attr_accessor :x, :y, :health, :direction, :bullets, :name, :score

  # Direction constants
  UP = 0
  RIGHT = 1
  DOWN = 2
  LEFT = 3

  # Player representation characters based on direction
  CHARS = {
    UP => '^',
    RIGHT => '>',
    DOWN => 'v',
    LEFT => '<'
  }

  def initialize(name, x = 10, y = 10)
    @name = name
    @x = x
    @y = y
    @health = 100
    @direction = RIGHT
    @bullets = []
    @score = 0
  end

  def move(direction, map_width, map_height)
    @direction = direction

    case direction
    when UP
      @y -= 1 if @y > 0
    when RIGHT
      @x += 1 if @x < map_width - 1
    when DOWN
      @y += 1 if @y < map_height - 1
    when LEFT
      @x -= 1 if @x > 0
    end
  end

  def shoot
    bullet_x, bullet_y = @x, @y

    # Position the bullet in front of the player based on direction
    case @direction
    when UP
      bullet_y -= 1
    when RIGHT
      bullet_x += 1
    when DOWN
      bullet_y += 1
    when LEFT
      bullet_x -= 1
    end

    @bullets << { x: bullet_x, y: bullet_y, direction: @direction }
  end

  def update_bullets(map_width, map_height)
    @bullets.each do |bullet|
      case bullet[:direction]
      when UP
        bullet[:y] -= 1
      when RIGHT
        bullet[:x] += 1
      when DOWN
        bullet[:y] += 1
      when LEFT
        bullet[:x] -= 1
      end
    end

    # Remove bullets that are out of bounds
    @bullets.reject! do |bullet|
      bullet[:x] < 0 || bullet[:x] >= map_width ||
      bullet[:y] < 0 || bullet[:y] >= map_height
    end
  end

  def hit
    @health -= 10
    @health = 0 if @health < 0
  end

  def alive?
    @health > 0
  end

  def char
    CHARS[@direction]
  end

  # Serialize player data for network transmission
  def to_hash
    {
      name: @name,
      x: @x,
      y: @y,
      health: @health,
      direction: @direction,
      bullets: @bullets,
      score: @score
    }
  end

  # Deserialize player data from network
  def update_from_hash(data)
    @x = data[:x]
    @y = data[:y]
    @health = data[:health]
    @direction = data[:direction]
    @bullets = data[:bullets]
    @score = data[:score]
  end
end

# Subprime Showdown

A terminal-based multiplayer shooter game with ASCII graphics.

## Features

- Terminal-based gameplay using the curses gem
- 1v1 multiplayer over network
- Top-down Doom-like perspective
- ASCII graphics
- Player movement and shooting mechanics
- Health and scoring system

## Requirements

- Ruby 2.5 or higher
- curses gem
- socket gem (standard library)
- json gem (standard library)

## Installation

1. Clone this repository:
   ```
   git clone https://github.com/yourusername/subprime_showdown.git
   cd subprime_showdown
   ```

2. Install required gems:

   Option 1: Using Bundler (recommended):
   ```
   bundle install
   ```

   Option 2: Install directly:
   ```
   gem install curses
   ```

## How to Play

### Starting the Game

Run the game with:
```
ruby game.rb
```

### Hosting a Game

1. Select option 1 to host a game
2. The game will display your IP address and port (default: 8080)
3. Share this information with the player who wants to join
4. Wait for the other player to connect

### Joining a Game

1. Select option 2 to join a game
2. Enter the host's IP address
3. Enter the port (default: 8080)
4. The game will connect to the host

### Controls

- Arrow keys: Move your character
- Spacebar: Shoot
- Q: Quit the game

## Game Mechanics

- Each player starts with 100 health
- Getting hit by a bullet reduces health by 10
- Hitting the opponent with a bullet gives you 10 points
- The game ends when one player's health reaches 0
- The player with remaining health wins

## Game Elements

- `^`, `>`, `v`, `<`: Player characters (direction indicated by the symbol)
- `*`: Bullets
- `#`: Walls
- ` `: Empty space

## Troubleshooting

- If you have trouble connecting, make sure your firewall allows connections on port 8080
- If the game crashes, try restarting it
- Make sure both players have the same version of the game

## License

This project is open source and available under the [MIT License](LICENSE).

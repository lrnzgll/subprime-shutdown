# Subprime Showdown

A terminal-based multiplayer shooting game with a client-server architecture.

## Overview

Subprime Showdown is a simple 2D shooting game where four players battle in a terminal-based arena. The game uses a client-server architecture where:

1. A central server manages the game state
2. Four clients connect to the server to play
3. Each client sends player actions to the server
4. The server broadcasts the game state to all clients

## Features

- Terminal-based gameplay using the curses gem
- 4-player multiplayer over network
- Top-down Doom-like perspective
- ASCII graphics
- Player movement and shooting mechanics
- Health and scoring system
- Client-server architecture for online play

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

See [how_do_we_run_it.md](how_do_we_run_it.md) for detailed instructions.

### Quick Start

1. Start the server:
   ```
   ruby server.rb
   ```

2. Start the client on each player's machine:
   ```
   ruby game.rb
   ```

3. Enter the server's IP address and port when prompted

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

## Architecture

The game uses a client-server architecture:

- **Server (server.rb)**: Manages connections, game state, and broadcasts updates
- **Client (game.rb)**: Handles user input, rendering, and communicates with the server
- **Networking (lib/networking.rb)**: Handles network communication
- **GameEngine (lib/game_engine.rb)**: Manages game logic and rendering
- **Player (lib/player.rb)**: Represents player state and actions

## Docker Support

The game server can be run in a Docker container. This is useful for hosting the server on a cloud provider or running it in a containerized environment.

### Building the Docker Image

To build the Docker image for the server:

```bash
docker build -t subprime-server .
```

### Running the Server in Docker

To run the server in a Docker container:

```bash
docker run -p 8080:8080 subprime-server
```

This will start the server and expose port 8080 to your host machine, allowing clients to connect.

### Connecting to the Dockerized Server

Clients can connect to the Dockerized server just like they would to a regular server. If the Docker container is running on the same machine as the client, use "localhost" as the server address. If it's running on a different machine, use that machine's IP address.

## Troubleshooting

- If you have trouble connecting, make sure your firewall allows connections on port 8080
- If the game crashes, try restarting it
- Make sure both players have the same version of the game
- When using Docker, ensure port 8080 is properly exposed and not blocked by firewalls

## License

This project is open source and available under the [MIT License](LICENSE).

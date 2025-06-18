FROM ruby:3.0-slim

WORKDIR /app

# Copy the server code and dependencies
COPY server.rb ./
COPY lib/ ./lib/

# Expose the port the server listens on
EXPOSE 8080

# Run the server when the container starts
CMD ["ruby", "server.rb"]

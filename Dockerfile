FROM ruby:3.0-slim

# Install OpenSSL development libraries
RUN apt-get update && apt-get install -y \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the server code and dependencies
COPY server.rb ./
COPY lib/ ./lib/
COPY Gemfile ./
COPY Gemfile.lock ./

# Install dependencies
RUN bundle install

# Expose the port the server listens on (Heroku will override this with $PORT)
EXPOSE 8080

# Run the server when the container starts
CMD ["ruby", "server.rb"]

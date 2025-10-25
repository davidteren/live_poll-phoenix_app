#!/bin/bash

# Basic setup for Elixir Phoenix project
echo "Setting up Elixir Phoenix environment..."

# Update package manager
apt-get update

# Install essential packages
apt-get install -y wget curl

# Install Erlang and Elixir from packages
wget -O- https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb > erlang-solutions.deb
dpkg -i erlang-solutions.deb
apt-get update
apt-get install -y esl-erlang elixir

# Install PostgreSQL
apt-get install -y postgresql postgresql-contrib

# Start PostgreSQL service
service postgresql start

# Configure postgres user
sudo -u postgres createuser --superuser postgres || echo "User already exists"
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'postgres';" || echo "Password already set"

# Install Node.js for asset compilation
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

# Install Elixir package managers
mix local.hex --force
mix local.rebar --force

# Navigate to project and install dependencies
cd /mnt/persist/workspace
mix deps.get

# Install Node.js dependencies
cd assets && npm install && cd ..

# Setup test database
MIX_ENV=test mix ecto.create --quiet
MIX_ENV=test mix ecto.migrate --quiet

# Compile the project
mix compile
FROM ruby:3.3.6

ENV LANG=C.UTF-8 \
    TZ=Asia/Kolkata

# Install base packages
RUN apt-get update -qq && apt-get install -y \
  build-essential \
  cmake \
  libpq-dev \
  curl \
  git \
  tzdata \
  libvips \
  libyaml-dev \
  pkg-config \
  --no-install-recommends && \
  apt-get clean && rm -rf /var/lib/apt/lists/*

# CockroachDB Cloud SSL: link system CA certs so sslmode=verify-full works
RUN mkdir -p /root/.postgresql && \
    ln -sf /etc/ssl/certs/ca-certificates.crt /root/.postgresql/root.crt

# Set working dir
WORKDIR /app

# Install Gems (bundle install before code for caching layer)
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3

# Add app source
COPY . .

# Use Docker-specific database.yml (supports staging + production via DATABASE_URL)
COPY config/database.yml.docker config/database.yml

# Expose port 3002 for pricing engine
EXPOSE 3002

# Start Puma (migrations run separately via deploy.sh)
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]

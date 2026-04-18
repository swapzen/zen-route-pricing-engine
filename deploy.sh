#!/bin/bash
set -e

ENV=${1:-staging}

if [ "$ENV" != "staging" ] && [ "$ENV" != "production" ]; then
  echo "Usage: ./deploy.sh [staging|production]"
  exit 1
fi

COMPOSE_FILE="docker-compose.${ENV}.yml"
ENV_FILE=".env.${ENV}"

if [ ! -f "$COMPOSE_FILE" ]; then
  echo "Error: $COMPOSE_FILE not found"
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "Error: $ENV_FILE not found. Create it with your secrets."
  exit 1
fi

echo "========================================="
echo " Deploying zen-route-pricing-engine ($ENV)"
echo "========================================="

# 1. Pull latest code
echo "→ Pulling latest code..."
git pull origin main

# 2. Build new image
echo "→ Building Docker image..."
docker compose -f $COMPOSE_FILE build

# 3. Run migrations BEFORE restarting (safe — uses a temporary container)
echo "→ Running migrations..."
docker compose -f $COMPOSE_FILE run --rm pricing bundle exec rails db:migrate
if [ $? -ne 0 ]; then
  echo "✗ Migration failed. Deployment aborted. Running containers unchanged."
  exit 1
fi

# 4. Restart services with new image
echo "→ Restarting services..."
docker compose -f $COMPOSE_FILE up -d

# 5. Wait and verify
echo "→ Waiting for health check..."
sleep 10

if docker ps | grep zen-pricing | grep -q "healthy\|Up"; then
  echo ""
  echo "========================================="
  echo " ✓ zen-route-pricing-engine ($ENV) deployed"
  echo "========================================="
  docker ps --format "table {{.Names}}\t{{.Status}}" | grep zen-pricing
else
  echo ""
  echo "⚠ Container may not be healthy yet. Check logs:"
  echo "  docker logs zen-pricing --tail 30"
fi

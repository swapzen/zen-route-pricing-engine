#!/bin/bash
set -e

ENV=${1:-staging}
CMD=${2:-deploy}

if [ "$ENV" != "staging" ] && [ "$ENV" != "production" ]; then
  echo "Usage: ./deploy.sh [staging|production] [deploy|status|logs|rollback]"
  exit 1
fi

SERVER="root@168.144.76.220"
APP_DIR="/opt/swapzen/zen-route-pricing-engine"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

header() { echo -e "\n${CYAN}═══════════════════════════════════════${NC}"; echo -e "${CYAN} $1${NC}"; echo -e "${CYAN}═══════════════════════════════════════${NC}\n"; }

ssh_run() { ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SERVER" "$1"; }

resolve_compose_file() {
  if [ "$ENV" = "production" ]; then
    if [ -f "docker-compose.prod.yml" ]; then
      echo "docker-compose.prod.yml"
      return
    fi
    if [ -f "docker-compose.production.yml" ]; then
      echo "docker-compose.production.yml"
      return
    fi
  fi

  if [ "$ENV" = "staging" ]; then
    if [ -f "docker-compose.staging.yml" ]; then
      echo "docker-compose.staging.yml"
      return
    fi
  fi

  echo "docker-compose.${ENV}.yml"
}

COMPOSE_FILE=$(resolve_compose_file)
echo -e "${YELLOW}Using compose file: ${COMPOSE_FILE}${NC}"

case $CMD in
  deploy)
    header "Deploying zen-route-pricing-engine ($ENV)"

    ssh_run "
      set -e
      cd ${APP_DIR}

      echo '→ Pulling latest code...'
      git pull origin main

      echo '→ Building Docker image...'
      docker compose -f ${COMPOSE_FILE} build

      echo '→ Running migrations...'
      docker compose -f ${COMPOSE_FILE} run --rm pricing bundle exec rails db:migrate || {
        echo '✗ Migration failed. Deployment aborted.'
        exit 1
      }

      echo '→ Restarting services...'
      docker compose -f ${COMPOSE_FILE} up -d

      echo '→ Waiting for health check...'
      sleep 10

      if docker ps | grep zen-pricing | grep -q 'healthy\|Up'; then
        echo ''
        echo '========================================='
        echo ' ✓ zen-route-pricing-engine (${ENV}) deployed'
        echo '========================================='
        docker ps --format 'table {{.Names}}\t{{.Status}}' | grep zen-pricing
      else
        echo '⚠ Container may not be healthy. Check: ./deploy.sh ${ENV} logs'
      fi
    "
    echo -e "\n${GREEN}✓ zen-route-pricing-engine deployed to ${ENV}${NC}"
    ;;

  status)
    header "zen-pricing status ($ENV)"
    ssh_run "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'NAMES|zen-pricing' || echo 'No containers found'"
    ;;

  logs)
    ssh_run "docker logs zen-pricing --tail 100 -f"
    ;;

  rollback)
    header "Rolling back zen-route-pricing-engine ($ENV)"
    ssh_run "
      set -e
      cd ${APP_DIR}
      docker compose -f ${COMPOSE_FILE} down
      git checkout HEAD~1
      docker compose -f ${COMPOSE_FILE} build
      docker compose -f ${COMPOSE_FILE} up -d
      sleep 10
      docker ps --format 'table {{.Names}}\t{{.Status}}' | grep zen-pricing
      echo '✓ Rolled back'
    "
    echo -e "\n${YELLOW}⚠ Rolled back${NC}"
    ;;

  *)
    echo "Usage: ./deploy.sh [staging|production] [deploy|status|logs|rollback]"
    ;;
esac

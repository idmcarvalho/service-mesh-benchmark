#!/bin/bash

# Service Mesh Benchmark - Deployment Script for Oracle Cloud
# This script deploys the application on Oracle Cloud infrastructure

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Service Mesh Benchmark - Oracle Cloud Deployment         ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo ""

# Check if .env.production exists
if [ ! -f .env.production ]; then
    echo -e "${RED}❌ Error: .env.production file not found${NC}"
    echo -e "${YELLOW}Please copy .env.production.example to .env.production and configure it${NC}"
    echo -e "${YELLOW}Command: cp .env.production.example .env.production${NC}"
    exit 1
fi

echo -e "${BLUE}📋 Loading environment variables...${NC}"
source .env.production

# Validate required environment variables
REQUIRED_VARS=("POSTGRES_PASSWORD" "REDIS_PASSWORD" "ALLOWED_ORIGINS" "API_URL" "GRAFANA_PASSWORD")
MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -ne 0 ]; then
    echo -e "${RED}❌ Error: Missing required environment variables:${NC}"
    for var in "${MISSING_VARS[@]}"; do
        echo -e "${RED}   - $var${NC}"
    done
    echo -e "${YELLOW}Please update .env.production with all required values${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Environment variables validated${NC}"
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Error: Docker is not running${NC}"
    echo -e "${YELLOW}Please start Docker and try again${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Docker is running${NC}"
echo ""

# Check if Docker Compose is available
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null 2>&1; then
    echo -e "${RED}❌ Error: Docker Compose is not installed${NC}"
    exit 1
fi

# Use docker-compose or docker compose based on availability
DOCKER_COMPOSE_CMD="docker compose"
if ! docker compose version &> /dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
fi

echo -e "${GREEN}✓ Docker Compose is available${NC}"
echo ""

# Stop existing containers
echo -e "${BLUE}🛑 Stopping existing containers...${NC}"
$DOCKER_COMPOSE_CMD -f docker-compose.prod.yml down || true
echo -e "${GREEN}✓ Stopped existing containers${NC}"
echo ""

# Pull latest images
echo -e "${BLUE}📥 Pulling latest base images...${NC}"
$DOCKER_COMPOSE_CMD -f docker-compose.prod.yml pull postgres redis prometheus grafana
echo -e "${GREEN}✓ Base images pulled${NC}"
echo ""

# Build application images
echo -e "${BLUE}🏗️  Building application images...${NC}"
$DOCKER_COMPOSE_CMD -f docker-compose.prod.yml build --no-cache api frontend
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Application images built successfully${NC}"
else
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi
echo ""

# Start services
echo -e "${BLUE}🚀 Starting services...${NC}"
$DOCKER_COMPOSE_CMD -f docker-compose.prod.yml up -d
echo -e "${GREEN}✓ Services started${NC}"
echo ""

# Wait for services to be healthy
echo -e "${BLUE}⏳ Waiting for services to be healthy...${NC}"
sleep 10

# Check database health
echo -e "${BLUE}   Checking PostgreSQL...${NC}"
for i in {1..30}; do
    if docker exec benchmark-postgres pg_isready -U benchmark > /dev/null 2>&1; then
        echo -e "${GREEN}   ✓ PostgreSQL is ready${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}   ❌ PostgreSQL failed to start${NC}"
        echo -e "${YELLOW}   Check logs: docker logs benchmark-postgres${NC}"
        exit 1
    fi
    sleep 2
done

# Check Redis health
echo -e "${BLUE}   Checking Redis...${NC}"
for i in {1..30}; do
    if docker exec benchmark-redis redis-cli -a "$REDIS_PASSWORD" --no-auth-warning ping > /dev/null 2>&1; then
        echo -e "${GREEN}   ✓ Redis is ready${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}   ❌ Redis failed to start${NC}"
        echo -e "${YELLOW}   Check logs: docker logs benchmark-redis${NC}"
        exit 1
    fi
    sleep 2
done

# Check API health
echo -e "${BLUE}   Checking API...${NC}"
for i in {1..60}; do
    if curl -s http://localhost:8000/health > /dev/null 2>&1; then
        echo -e "${GREEN}   ✓ API is ready${NC}"
        break
    fi
    if [ $i -eq 60 ]; then
        echo -e "${RED}   ❌ API failed to start${NC}"
        echo -e "${YELLOW}   Check logs: docker logs benchmark-api${NC}"
        exit 1
    fi
    sleep 2
done

# Check Frontend health
echo -e "${BLUE}   Checking Frontend...${NC}"
for i in {1..60}; do
    if curl -s http://localhost:3000 > /dev/null 2>&1; then
        echo -e "${GREEN}   ✓ Frontend is ready${NC}"
        break
    fi
    if [ $i -eq 60 ]; then
        echo -e "${RED}   ❌ Frontend failed to start${NC}"
        echo -e "${YELLOW}   Check logs: docker logs benchmark-frontend${NC}"
        exit 1
    fi
    sleep 2
done

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            Deployment Successful! 🎉                       ║${NC}"
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo ""
echo -e "${BLUE}Services are now running at:${NC}"
echo -e "${GREEN}  Frontend:    http://localhost:3000${NC}"
echo -e "${GREEN}  API:         http://localhost:8000${NC}"
echo -e "${GREEN}  API Docs:    http://localhost:8000/docs${NC}"
echo -e "${GREEN}  Prometheus:  http://localhost:9090${NC}"
echo -e "${GREEN}  Grafana:     http://localhost:3001${NC}"
echo ""
echo -e "${BLUE}Grafana credentials:${NC}"
echo -e "  Username: ${GRAFANA_USER:-admin}"
echo -e "  Password: ${GRAFANA_PASSWORD}"
echo ""
echo -e "${YELLOW}📝 Useful commands:${NC}"
echo -e "  View logs:        $DOCKER_COMPOSE_CMD -f docker-compose.prod.yml logs -f"
echo -e "  Stop services:    $DOCKER_COMPOSE_CMD -f docker-compose.prod.yml down"
echo -e "  Restart:          $DOCKER_COMPOSE_CMD -f docker-compose.prod.yml restart"
echo -e "  Check status:     $DOCKER_COMPOSE_CMD -f docker-compose.prod.yml ps"
echo ""

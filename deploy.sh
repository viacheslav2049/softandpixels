#!/bin/bash
set -e

SERVER=192.3.36.171
APP_DIR=/root/projects/softandpixels
USER=root
BRANCH=$(git branch --show-current)

echo "🚀 Deploy started (branch: $BRANCH)..."

# Push code via deploy remote (bare repo on server)
echo "📤 Pushing code to server $BRANCH branch..."
git push deploy "$BRANCH"

# Copy .env
echo "🔑 Copying environment file..."
scp .env "$USER@$SERVER:$APP_DIR/.env"

# Remote deploy
ssh "$USER@$SERVER" << EOF
  set -e

  cd "$APP_DIR"

  echo "📥 Pulling latest code..."
  git pull

  echo "🐳 Rebuilding and restarting containers..."
  docker-compose up -d --build

  # echo "🧹 Cleaning up old images..."
  # docker image prune -f

  # echo "✅ Deploy finished!"
EOF

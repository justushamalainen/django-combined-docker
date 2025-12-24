#!/bin/bash
set -e

# Django + Nginx + Gunicorn + Config API Startup Script
# This script is designed to be run by tini as PID 1

echo "=== Starting Django Application ==="

# Configuration (can be overridden by environment variables)
GUNICORN_WORKERS=${GUNICORN_WORKERS:-2}
GUNICORN_THREADS=${GUNICORN_THREADS:-4}
GUNICORN_BIND=${GUNICORN_BIND:-127.0.0.1:8000}
GUNICORN_TIMEOUT=${GUNICORN_TIMEOUT:-30}

# Config API settings
NGINX_CONFIG_API_PORT=${NGINX_CONFIG_API_PORT:-8081}
ENABLE_CONFIG_API=${ENABLE_CONFIG_API:-true}

# Wait for dependencies (if any)
if [ -n "$WAIT_FOR_HOST" ] && [ -n "$WAIT_FOR_PORT" ]; then
    echo "Waiting for $WAIT_FOR_HOST:$WAIT_FOR_PORT..."
    while ! nc -z "$WAIT_FOR_HOST" "$WAIT_FOR_PORT"; do
        sleep 1
    done
    echo "$WAIT_FOR_HOST:$WAIT_FOR_PORT is available"
fi

# Run Django migrations
echo "Running database migrations..."
python manage.py migrate --noinput

# Collect static files
echo "Collecting static files..."
python manage.py collectstatic --noinput

# Create required directories
mkdir -p /app/media/uploads
mkdir -p /var/lib/nginx-api
mkdir -p /var/backups/nginx
mkdir -p /etc/nginx/conf.d

# Function to handle shutdown gracefully
shutdown() {
    echo "Shutting down..."

    # Stop nginx gracefully
    if [ -f /tmp/nginx.pid ]; then
        nginx -s quit 2>/dev/null || true
    fi

    # Stop gunicorn gracefully
    if [ -n "$GUNICORN_PID" ]; then
        kill -TERM "$GUNICORN_PID" 2>/dev/null || true
        wait "$GUNICORN_PID" 2>/dev/null || true
    fi

    # Stop config API gracefully
    if [ -n "$CONFIG_API_PID" ]; then
        kill -TERM "$CONFIG_API_PID" 2>/dev/null || true
        wait "$CONFIG_API_PID" 2>/dev/null || true
    fi

    echo "Shutdown complete"
    exit 0
}

# Trap signals for graceful shutdown
trap shutdown SIGTERM SIGINT SIGQUIT

# Start Nginx Config API if enabled
CONFIG_API_PID=""
if [ "$ENABLE_CONFIG_API" = "true" ]; then
    echo "Starting Nginx Config API on port $NGINX_CONFIG_API_PORT..."
    python /app/scripts/nginx_config_api.py &
    CONFIG_API_PID=$!

    # Wait a moment for the API to start
    sleep 1

    if ! kill -0 "$CONFIG_API_PID" 2>/dev/null; then
        echo "WARNING: Config API failed to start, continuing without it"
        CONFIG_API_PID=""
    else
        echo "Config API started with PID $CONFIG_API_PID"
    fi
fi

echo "Starting Gunicorn with $GUNICORN_WORKERS workers and $GUNICORN_THREADS threads..."

# Start Gunicorn in the background
gunicorn myproject.wsgi:application \
    --bind "$GUNICORN_BIND" \
    --workers "$GUNICORN_WORKERS" \
    --threads "$GUNICORN_THREADS" \
    --timeout "$GUNICORN_TIMEOUT" \
    --access-logfile - \
    --error-logfile - \
    --capture-output \
    --enable-stdio-inheritance \
    &

GUNICORN_PID=$!

# Wait a moment for Gunicorn to start
sleep 2

# Check if Gunicorn started successfully
if ! kill -0 "$GUNICORN_PID" 2>/dev/null; then
    echo "ERROR: Gunicorn failed to start"
    exit 1
fi

echo "Gunicorn started with PID $GUNICORN_PID"

echo "Starting Nginx..."

# Start Nginx in the foreground (daemon off is set in config)
# This keeps the container running
nginx -c /etc/nginx/nginx.conf &

NGINX_PID=$!

# Wait a moment for Nginx to start
sleep 1

if ! kill -0 "$NGINX_PID" 2>/dev/null; then
    echo "ERROR: Nginx failed to start"
    exit 1
fi

echo "Nginx started with PID $NGINX_PID"
echo ""
echo "=== Application Ready ==="
echo "  - Nginx listening on port 80"
echo "  - Gunicorn listening on $GUNICORN_BIND"
if [ -n "$CONFIG_API_PID" ]; then
    echo "  - Config API listening on port $NGINX_CONFIG_API_PORT"
    echo "  - Config API available at /api/nginx/"
    echo ""
    echo "Dynamic Backend API endpoints:"
    echo "  GET    /api/nginx/routes          - List all routes"
    echo "  POST   /api/nginx/routes          - Add/update route"
    echo "  DELETE /api/nginx/routes/<path>   - Delete route"
    echo "  GET    /api/nginx/config/preview  - Preview config"
    echo "  POST   /api/nginx/config/reload   - Force reload"
fi
echo ""

# Build list of PIDs to wait for
PIDS="$GUNICORN_PID $NGINX_PID"
if [ -n "$CONFIG_API_PID" ]; then
    PIDS="$PIDS $CONFIG_API_PID"
fi

# Wait for any process to exit
wait -n $PIDS

# If we get here, one of the processes died
echo "ERROR: One of the processes exited unexpectedly"
shutdown
exit 1

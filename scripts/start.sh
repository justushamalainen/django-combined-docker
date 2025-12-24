#!/bin/bash
set -e

# Django + Nginx + Gunicorn Startup Script
# This script is designed to be run by tini as PID 1

echo "=== Starting Django Application ==="

# Configuration (can be overridden by environment variables)
GUNICORN_WORKERS=${GUNICORN_WORKERS:-2}
GUNICORN_THREADS=${GUNICORN_THREADS:-4}
GUNICORN_BIND=${GUNICORN_BIND:-127.0.0.1:8000}
GUNICORN_TIMEOUT=${GUNICORN_TIMEOUT:-30}

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

# Create media directory if it doesn't exist
mkdir -p /app/media/uploads

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

    echo "Shutdown complete"
    exit 0
}

# Trap signals for graceful shutdown
trap shutdown SIGTERM SIGINT SIGQUIT

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

echo "Nginx started with PID $NGINX_PID"
echo "=== Application Ready ==="
echo "  - Nginx listening on port 80"
echo "  - Gunicorn listening on $GUNICORN_BIND"

# Wait for either process to exit
wait -n "$GUNICORN_PID" "$NGINX_PID"

# If we get here, one of the processes died
echo "ERROR: One of the processes exited unexpectedly"
shutdown
exit 1

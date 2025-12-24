# Django + Nginx + Gunicorn Docker Image
# Uses tini as init system (PID 1)
# Includes dynamic Nginx configuration API

FROM python:3.12-slim-bookworm

# Build arguments
ARG TINI_VERSION=v0.19.0

# Environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    APP_HOME=/app

# Environment variables for dynamic config API
ENV NGINX_CONFIG_API_PORT=8081 \
    NGINX_DYNAMIC_CONF_PATH=/etc/nginx/conf.d/dynamic_backends.conf \
    ROUTES_DB_PATH=/var/lib/nginx-api/routes.json \
    NGINX_BACKUP_DIR=/var/backups/nginx \
    ENABLE_CONFIG_API=true

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx \
    netcat-openbsd \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Install tini
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN chmod +x /tini

# Create app user for security
RUN groupadd --gid 1000 appgroup \
    && useradd --uid 1000 --gid appgroup --shell /bin/bash --create-home appuser

# Create necessary directories
RUN mkdir -p ${APP_HOME} \
    ${APP_HOME}/staticfiles \
    ${APP_HOME}/media \
    ${APP_HOME}/scripts \
    /var/log/nginx \
    /var/lib/nginx \
    /var/lib/nginx-api \
    /var/backups/nginx \
    /run/nginx \
    /etc/nginx/conf.d \
    && chown -R appuser:appgroup ${APP_HOME} \
    && chown -R appuser:appgroup /var/log/nginx \
    && chown -R appuser:appgroup /var/lib/nginx \
    && chown -R appuser:appgroup /var/lib/nginx-api \
    && chown -R appuser:appgroup /var/backups/nginx \
    && chown -R appuser:appgroup /run/nginx \
    && chown -R appuser:appgroup /etc/nginx/conf.d

# Set working directory
WORKDIR ${APP_HOME}

# Copy and install Python dependencies first (for better caching)
COPY --chown=appuser:appgroup requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy nginx configuration
COPY --chown=appuser:appgroup nginx/nginx.conf /etc/nginx/nginx.conf

# Copy application code
COPY --chown=appuser:appgroup myproject/ ${APP_HOME}/myproject/
COPY --chown=appuser:appgroup templates/ ${APP_HOME}/templates/
COPY --chown=appuser:appgroup static/ ${APP_HOME}/static/
COPY --chown=appuser:appgroup manage.py ${APP_HOME}/

# Copy scripts (startup and config API)
COPY --chown=appuser:appgroup scripts/ ${APP_HOME}/scripts/
COPY --chown=appuser:appgroup scripts/start.sh /start.sh
RUN chmod +x /start.sh ${APP_HOME}/scripts/*.sh ${APP_HOME}/scripts/*.py 2>/dev/null || true

# Fix nginx permissions for non-root user
RUN touch /tmp/nginx.pid \
    && chown appuser:appgroup /tmp/nginx.pid \
    && chmod 644 /etc/nginx/nginx.conf

# Switch to non-root user
USER appuser

# Expose ports
# 80 - Nginx (main entry point)
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost/nginx-health || exit 1

# Use tini as init system
ENTRYPOINT ["/tini", "--"]

# Start the application
CMD ["/start.sh"]

# Django + Nginx + Gunicorn Docker Setup

A production-ready Docker image that runs Django with Gunicorn behind an Nginx reverse proxy, all managed by Tini as the init system. Includes a dynamic Nginx configuration API for runtime backend management.

## Features

- **Tini** - Minimal init system for proper PID 1 handling and signal forwarding
- **Nginx** - Reverse proxy with single worker mode, serves static and media files directly
- **Gunicorn** - WSGI HTTP server for Django
- **Django** - Example project with static files, media uploads, and health checks
- **Dynamic Config API** - REST API to manage Nginx backend routes at runtime
- **Non-root user** - Runs as unprivileged user for security
- **Health checks** - Built-in health check endpoints

## Quick Start

### Build and Run with Docker Compose

```bash
# Build and start the container
docker-compose up --build

# Access the application
open http://localhost:8080
```

### Build and Run with Docker

```bash
# Build the image
docker build -t django-nginx-gunicorn .

# Run the container
docker run -p 8080:80 \
  -e DJANGO_SECRET_KEY=your-secret-key \
  -e DJANGO_DEBUG=False \
  -e DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1 \
  django-nginx-gunicorn
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DJANGO_SECRET_KEY` | (insecure default) | Django secret key |
| `DJANGO_DEBUG` | `False` | Enable Django debug mode |
| `DJANGO_ALLOWED_HOSTS` | `localhost,127.0.0.1` | Comma-separated allowed hosts |
| `GUNICORN_WORKERS` | `2` | Number of Gunicorn workers |
| `GUNICORN_THREADS` | `4` | Number of threads per worker |
| `GUNICORN_TIMEOUT` | `30` | Worker timeout in seconds |
| `GUNICORN_BIND` | `127.0.0.1:8000` | Gunicorn bind address |
| `ENABLE_CONFIG_API` | `true` | Enable dynamic Nginx config API |
| `NGINX_CONFIG_API_PORT` | `8081` | Port for config API (internal) |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Docker Container                          │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                      Tini (PID 1)                            │ │
│  │           Signal forwarding & zombie reaping                 │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                              │                                    │
│              ┌───────────────┼───────────────┐                   │
│              ▼               ▼               ▼                   │
│  ┌───────────────────┐ ┌───────────────┐ ┌───────────────────┐  │
│  │  Nginx (:80)      │ │ Gunicorn      │ │ Config API        │  │
│  │  - Reverse proxy  │ │ (:8000)       │ │ (:8081)           │  │
│  │  - Static files   │ │ - WSGI server │ │ - Route mgmt      │  │
│  │  - Media files    │ │ - Django app  │ │ - Live reload     │  │
│  │  - Dynamic routes │ │               │ │                   │  │
│  └───────────────────┘ └───────────────┘ └───────────────────┘  │
│           │                                       │              │
│           └──────────── Dynamic Config ───────────┘              │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Endpoints

### Django Application

| Endpoint | Description |
|----------|-------------|
| `/` | Home page |
| `/health/` | Django health check (JSON) |
| `/nginx-health` | Nginx health check |
| `/upload/` | File upload test |
| `/admin/` | Django admin |
| `/static/` | Static files (served by Nginx) |
| `/media/` | Media files (served by Nginx) |

### Dynamic Config API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/nginx/` | GET | API info and available endpoints |
| `/api/nginx/routes` | GET | List all configured routes |
| `/api/nginx/routes` | POST | Add or update a route |
| `/api/nginx/routes/<path>` | GET | Get specific route details |
| `/api/nginx/routes/<path>` | DELETE | Delete a route |
| `/api/nginx/routes` | DELETE | Delete all routes |
| `/api/nginx/routes/batch` | POST | Batch add/update routes |
| `/api/nginx/config/preview` | GET | Preview generated Nginx config |
| `/api/nginx/config/reload` | POST | Force reload Nginx |
| `/api/nginx/config/backups` | GET | List config backups |
| `/api/nginx/config/rollback` | POST | Rollback to a backup |
| `/api/nginx/health` | GET | Config API health check |

## Dynamic Backend Configuration

The Config API allows you to dynamically add, remove, and modify backend routes without restarting the container.

### Add a Route

```bash
curl -X POST http://localhost:8080/api/nginx/routes \
  -H "Content-Type: application/json" \
  -d '{
    "path": "/api/users/",
    "backends": [
      {"address": "10.0.0.1", "port": 8080, "weight": 5},
      {"address": "10.0.0.2", "port": 8080, "weight": 3},
      {"address": "10.0.0.3", "port": 8080, "backup": true}
    ],
    "options": {
      "connect_timeout": 5,
      "read_timeout": 60,
      "send_timeout": 60
    }
  }'
```

### Backend Options

Each backend in the `backends` array supports:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `address` | string | Yes | Backend IP or hostname |
| `port` | integer | Yes | Backend port (1-65535) |
| `weight` | integer | No | Load balancing weight (default: 1) |
| `max_fails` | integer | No | Max failures before marking down |
| `fail_timeout` | integer | No | Time to consider server unavailable |
| `backup` | boolean | No | Use only when primary servers are down |
| `down` | boolean | No | Mark server as permanently unavailable |

### Route Options

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `connect_timeout` | integer | 5 | Connection timeout in seconds |
| `read_timeout` | integer | 60 | Read timeout in seconds |
| `send_timeout` | integer | 60 | Send timeout in seconds |

### Batch Update Routes

```bash
curl -X POST http://localhost:8080/api/nginx/routes/batch \
  -H "Content-Type: application/json" \
  -d '{
    "routes": [
      {
        "path": "/api/v1/",
        "backends": [{"address": "api-v1", "port": 8000}]
      },
      {
        "path": "/api/v2/",
        "backends": [{"address": "api-v2", "port": 8000}]
      }
    ]
  }'
```

### List Routes

```bash
curl http://localhost:8080/api/nginx/routes
```

### Delete a Route

```bash
curl -X DELETE http://localhost:8080/api/nginx/routes/api/users/
```

### Preview Configuration

```bash
curl http://localhost:8080/api/nginx/config/preview
```

### Rollback Configuration

```bash
# List available backups
curl http://localhost:8080/api/nginx/config/backups

# Rollback to a specific backup
curl -X POST http://localhost:8080/api/nginx/config/rollback \
  -H "Content-Type: application/json" \
  -d '{"backup": "dynamic_backends.20240101_120000.conf"}'
```

## Accessing Dynamic Backends

Routes configured via the Config API are available through the `/proxy/` prefix:

```bash
# If you configured a route for /api/users/
# Access it via:
curl http://localhost:8080/proxy/api/users/
```

## Project Structure

```
.
├── Dockerfile              # Docker build configuration
├── docker-compose.yml      # Docker Compose configuration
├── requirements.txt        # Python dependencies
├── manage.py              # Django management script
├── myproject/             # Django project
│   ├── __init__.py
│   ├── settings.py
│   ├── urls.py
│   ├── wsgi.py
│   └── core/              # Example app
│       ├── __init__.py
│       ├── apps.py
│       ├── urls.py
│       └── views.py
├── templates/             # Django templates
│   ├── base.html
│   └── core/
│       ├── home.html
│       └── upload.html
├── static/                # Static files
│   ├── css/
│   │   └── style.css
│   └── images/
│       └── test.svg
├── media/                 # User uploaded files
├── nginx/
│   └── nginx.conf         # Nginx configuration
└── scripts/
    ├── start.sh           # Startup script
    └── nginx_config_api.py # Dynamic config API
```

## Data Persistence

The following data is persisted via Docker volumes:

| Volume | Path | Description |
|--------|------|-------------|
| `media_data` | `/app/media` | User uploaded files |
| `db_data` | `/app/db` | SQLite database |
| `nginx_routes` | `/var/lib/nginx-api` | Route configurations |
| `nginx_backups` | `/var/backups/nginx` | Config backups |

## Why Tini?

Tini is a minimal init system that:
- Properly handles PID 1 responsibilities
- Forwards signals to child processes
- Reaps zombie processes
- Ensures clean container shutdown

## Why Single Container?

This setup combines Nginx, Gunicorn, and the Config API in a single container for:
- Simpler deployment in environments that don't support sidecars
- Reduced inter-container networking overhead
- Easier local development and testing
- Lower resource overhead for small deployments

For production at scale, consider separating services into separate containers.

## License

MIT

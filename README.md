# Django + Nginx + Gunicorn Docker Setup

A production-ready Docker image that runs Django with Gunicorn behind an Nginx reverse proxy, all managed by Tini as the init system.

## Features

- **Tini** - Minimal init system for proper PID 1 handling and signal forwarding
- **Nginx** - Reverse proxy with single worker mode, serves static and media files directly
- **Gunicorn** - WSGI HTTP server for Django
- **Django** - Example project with static files, media uploads, and health checks
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

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                    Docker Container                   │
│                                                       │
│  ┌─────────────────────────────────────────────────┐ │
│  │                    Tini (PID 1)                  │ │
│  │         Signal forwarding & zombie reaping      │ │
│  └─────────────────────────────────────────────────┘ │
│                          │                            │
│                    ┌─────┴─────┐                     │
│                    ▼           ▼                     │
│  ┌─────────────────────┐ ┌─────────────────────────┐ │
│  │   Nginx (:80)       │ │   Gunicorn (:8000)      │ │
│  │   - Reverse proxy   │ │   - WSGI server         │ │
│  │   - Static files    │ │   - Django app          │ │
│  │   - Media files     │ │                         │ │
│  └─────────────────────┘ └─────────────────────────┘ │
│                                                       │
└──────────────────────────────────────────────────────┘
```

## Endpoints

| Endpoint | Description |
|----------|-------------|
| `/` | Home page |
| `/health/` | Django health check (JSON) |
| `/nginx-health` | Nginx health check |
| `/upload/` | File upload test |
| `/admin/` | Django admin |
| `/static/` | Static files (served by Nginx) |
| `/media/` | Media files (served by Nginx) |

## Project Structure

```
.
├── Dockerfile              # Multi-stage Docker build
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
    └── start.sh           # Startup script
```

## Why Tini?

Tini is a minimal init system that:
- Properly handles PID 1 responsibilities
- Forwards signals to child processes
- Reaps zombie processes
- Ensures clean container shutdown

## Why Single Container?

This setup combines Nginx and Gunicorn in a single container for:
- Simpler deployment in environments that don't support sidecars
- Reduced inter-container networking overhead
- Easier local development and testing
- Lower resource overhead for small deployments

For production at scale, consider separating Nginx and Django into separate containers.

## License

MIT

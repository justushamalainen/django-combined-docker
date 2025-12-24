#!/usr/bin/env python3
"""
Django + Nginx + Gunicorn Startup Script

This script manages the lifecycle of Gunicorn and Nginx processes.
Designed to be run by tini as PID 1's child process.
"""

import os
import sys
import signal
import subprocess
import time
from typing import Optional

# Ensure unbuffered output for proper logging
os.environ['PYTHONUNBUFFERED'] = '1'


class ProcessManager:
    """Manages Gunicorn and Nginx processes with proper signal handling."""

    def __init__(self):
        self.gunicorn_proc: Optional[subprocess.Popen] = None
        self.nginx_proc: Optional[subprocess.Popen] = None
        self.shutting_down = False

        # Configuration from environment
        self.gunicorn_workers = os.environ.get('GUNICORN_WORKERS', '2')
        self.gunicorn_threads = os.environ.get('GUNICORN_THREADS', '4')
        self.gunicorn_bind = os.environ.get('GUNICORN_BIND', '127.0.0.1:8000')
        self.gunicorn_timeout = os.environ.get('GUNICORN_TIMEOUT', '30')

    def log(self, message: str):
        """Print log message with flush for immediate output."""
        print(f"[startup] {message}", flush=True)

    def run_django_command(self, *args) -> bool:
        """Run a Django management command."""
        cmd = ['python', 'manage.py'] + list(args)
        self.log(f"Running: {' '.join(cmd)}")
        result = subprocess.run(cmd, env=os.environ)
        return result.returncode == 0

    def wait_for_dependency(self):
        """Wait for external dependency if configured."""
        host = os.environ.get('WAIT_FOR_HOST')
        port = os.environ.get('WAIT_FOR_PORT')

        if not host or not port:
            return

        import socket
        self.log(f"Waiting for {host}:{port}...")

        while True:
            try:
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                    s.settimeout(1)
                    s.connect((host, int(port)))
                    self.log(f"{host}:{port} is available")
                    return
            except (socket.error, socket.timeout):
                time.sleep(1)

    def start_gunicorn(self) -> bool:
        """Start Gunicorn process."""
        cmd = [
            'gunicorn',
            'myproject.wsgi:application',
            '--bind', self.gunicorn_bind,
            '--workers', self.gunicorn_workers,
            '--threads', self.gunicorn_threads,
            '--timeout', self.gunicorn_timeout,
            '--access-logfile', '-',
            '--error-logfile', '-',
            '--capture-output',
            '--enable-stdio-inheritance',
        ]

        self.log(f"Starting Gunicorn: {' '.join(cmd)}")

        # Start gunicorn with stdout/stderr going to our stdout/stderr
        self.gunicorn_proc = subprocess.Popen(
            cmd,
            stdout=sys.stdout,
            stderr=sys.stderr,
            env=os.environ,
        )

        # Wait a moment for startup
        time.sleep(2)

        # Check if it started successfully
        if self.gunicorn_proc.poll() is not None:
            self.log("ERROR: Gunicorn failed to start")
            return False

        self.log(f"Gunicorn started with PID {self.gunicorn_proc.pid}")
        return True

    def start_nginx(self) -> bool:
        """Start Nginx process."""
        cmd = ['nginx', '-c', '/etc/nginx/nginx.conf']

        self.log(f"Starting Nginx: {' '.join(cmd)}")

        # Start nginx with stdout/stderr going to our stdout/stderr
        self.nginx_proc = subprocess.Popen(
            cmd,
            stdout=sys.stdout,
            stderr=sys.stderr,
            env=os.environ,
        )

        # Wait a moment for startup
        time.sleep(1)

        # Check if it started successfully
        if self.nginx_proc.poll() is not None:
            self.log("ERROR: Nginx failed to start")
            return False

        self.log(f"Nginx started with PID {self.nginx_proc.pid}")
        return True

    def shutdown(self, signum=None, frame=None):
        """Gracefully shutdown all processes."""
        if self.shutting_down:
            return
        self.shutting_down = True

        sig_name = signal.Signals(signum).name if signum else "unknown"
        self.log(f"Shutting down (received {sig_name})...")

        # Stop Nginx gracefully
        if self.nginx_proc and self.nginx_proc.poll() is None:
            self.log("Stopping Nginx...")
            try:
                subprocess.run(['nginx', '-s', 'quit'], timeout=5)
                self.nginx_proc.wait(timeout=10)
            except Exception as e:
                self.log(f"Nginx shutdown error: {e}")
                self.nginx_proc.kill()

        # Stop Gunicorn gracefully
        if self.gunicorn_proc and self.gunicorn_proc.poll() is None:
            self.log("Stopping Gunicorn...")
            try:
                self.gunicorn_proc.terminate()
                self.gunicorn_proc.wait(timeout=10)
            except Exception as e:
                self.log(f"Gunicorn shutdown error: {e}")
                self.gunicorn_proc.kill()

        self.log("Shutdown complete")

    def setup_signal_handlers(self):
        """Setup signal handlers for graceful shutdown."""
        signal.signal(signal.SIGTERM, self.shutdown)
        signal.signal(signal.SIGINT, self.shutdown)
        signal.signal(signal.SIGQUIT, self.shutdown)

    def monitor_processes(self):
        """Monitor processes and exit if either dies."""
        self.log("Monitoring processes...")

        while not self.shutting_down:
            # Check Gunicorn
            if self.gunicorn_proc and self.gunicorn_proc.poll() is not None:
                self.log(f"ERROR: Gunicorn exited with code {self.gunicorn_proc.returncode}")
                return False

            # Check Nginx
            if self.nginx_proc and self.nginx_proc.poll() is not None:
                self.log(f"ERROR: Nginx exited with code {self.nginx_proc.returncode}")
                return False

            time.sleep(1)

        return True

    def run(self) -> int:
        """Main entry point."""
        self.log("=== Starting Django Application ===")

        # Setup signal handlers
        self.setup_signal_handlers()

        # Wait for dependencies
        self.wait_for_dependency()

        # Run Django setup
        self.log("Running database migrations...")
        if not self.run_django_command('migrate', '--noinput'):
            self.log("ERROR: Migrations failed")
            return 1

        self.log("Collecting static files...")
        if not self.run_django_command('collectstatic', '--noinput'):
            self.log("ERROR: collectstatic failed")
            return 1

        # Create media directory
        os.makedirs('/app/media/uploads', exist_ok=True)

        # Start services
        if not self.start_gunicorn():
            return 1

        if not self.start_nginx():
            self.shutdown()
            return 1

        self.log("=== Application Ready ===")
        self.log(f"  - Nginx listening on port 80")
        self.log(f"  - Gunicorn listening on {self.gunicorn_bind}")

        # Monitor processes
        success = self.monitor_processes()

        # Cleanup
        self.shutdown()

        return 0 if success else 1


if __name__ == '__main__':
    manager = ProcessManager()
    sys.exit(manager.run())

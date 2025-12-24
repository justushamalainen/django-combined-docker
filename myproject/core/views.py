from django.shortcuts import render
from django.http import JsonResponse
import os


def home(request):
    """Home page view."""
    return render(request, 'core/home.html', {
        'title': 'Django + Nginx + Gunicorn Docker Setup',
    })


def health_check(request):
    """Health check endpoint for container orchestration."""
    return JsonResponse({
        'status': 'healthy',
        'service': 'django-app',
    })


def upload_test(request):
    """Simple file upload test view."""
    if request.method == 'POST' and request.FILES.get('file'):
        uploaded_file = request.FILES['file']
        # Save to media directory
        file_path = os.path.join('uploads', uploaded_file.name)
        full_path = os.path.join('/app/media', file_path)

        os.makedirs(os.path.dirname(full_path), exist_ok=True)

        with open(full_path, 'wb+') as destination:
            for chunk in uploaded_file.chunks():
                destination.write(chunk)

        return JsonResponse({
            'status': 'success',
            'file_url': f'/media/{file_path}',
        })

    return render(request, 'core/upload.html')

"""Службові в'юхи застосунку.

Головна сторінка друкує змінні середовища, які приїхали з ConfigMap та Secret —
це найпростіший спосіб довести, що застосунок справді їх читає. `healthz`
використовується як liveness- і readiness-проба в Deployment.
"""

import os

from django.db import connections
from django.http import JsonResponse

# Значення з ConfigMap показуємо як є; значення з Secret — лише факт наявності.
CONFIG_KEYS = (
    'DJANGO_ENV',
    'DJANGO_DEBUG',
    'DJANGO_ALLOWED_HOSTS',
    'DJANGO_SETTINGS_MODULE',
    'POSTGRES_DB',
    'POSTGRES_USER',
    'POSTGRES_HOST',
    'POSTGRES_PORT',
)

SECRET_KEYS = (
    'POSTGRES_PASSWORD',
    'DJANGO_SECRET_KEY',
)


def _database_status():
    """Стан підключення до PostgreSQL — без винятків назовні."""
    try:
        connections['default'].cursor()
    except Exception as exc:  # noqa: BLE001 — статус, а не обробка помилки
        return 'unavailable ({})'.format(exc.__class__.__name__)
    return 'ok'


def index(request):
    return JsonResponse(
        {
            'app': 'django-app',
            'pod': os.environ.get('POD_NAME', os.environ.get('HOSTNAME', 'unknown')),
            'database': _database_status(),
            'config': {key: os.environ.get(key) for key in CONFIG_KEYS},
            'secrets': {
                key: 'set' if os.environ.get(key) else 'not set'
                for key in SECRET_KEYS
            },
        },
        json_dumps_params={'indent': 2},
    )


def healthz(request):
    """Завжди 200: под живий навіть тоді, коли база тимчасово недоступна."""
    return JsonResponse({'status': 'ok', 'database': _database_status()})

FROM python:3.9-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Контекст збірки — уся папка Django/, а код лежить в її підпапці app/.
# requirements.txt копіюємо окремим шаром до самого коду: поки список
# залежностей не змінився, `pip install` бере результат з кешу, а не
# качає пакети заново на кожен коміт.
COPY app/requirements.txt /app/
RUN pip install --upgrade pip && pip install -r requirements.txt

COPY app/ /app/

EXPOSE 8000

CMD ["gunicorn", "myproject.wsgi:application", \
     "--bind", "0.0.0.0:8000", \
     "--workers", "2", \
     "--access-logfile", "-"]

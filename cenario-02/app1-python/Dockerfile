FROM python:3.12-slim AS builder
WORKDIR /build

# Instala compiladores apenas no stage de build
RUN apt-get update && apt-get install -y build-essential libpq-dev && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim
WORKDIR /app

# Instala curl (para healthcheck)
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

COPY --from=builder /install /usr/local
COPY app.py .

EXPOSE 5000

# Cria usuário não privilegiado
RUN useradd -m appuser
USER appuser

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--access-logfile", "-", "app:app"]

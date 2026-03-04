#!/usr/bin/env sh
set -e

CERT_DIR="/certs"
KEY="$CERT_DIR/nginx.key"
CRT="$CERT_DIR/nginx.crt"
DAYS=825   # máximo aceito por Chrome para self-signed

# Se os arquivos já existem e ainda são válidos, não regera
if [ -f "$KEY" ] && [ -f "$CRT" ]; then
  EXPIRY=$(openssl x509 -enddate -noout -in "$CRT" | cut -d= -f2)
  echo "[cert-gen] Certificado existente válido até: $EXPIRY — pulando geração"
  exit 0
fi

echo "[cert-gen] Gerando certificado TLS self-signed ($DAYS dias)..."

openssl req -x509 -nodes -newkey rsa:4096 \
  -keyout "$KEY" \
  -out    "$CRT" \
  -days   "$DAYS" \
  -subj   "/C=BR/ST=SP/L=SaoPaulo/O=DevOps Challenge/OU=CI/CN=devops-challenge.local" \
  -addext "subjectAltName=DNS:devops-challenge.local,DNS:localhost,IP:127.0.0.1"

chmod 644 "$CRT"
chmod 600 "$KEY"

echo "[cert-gen] ✅ Certificado gerado em $CERT_DIR"
ls -lh "$CERT_DIR"

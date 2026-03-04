# DevOps Challenge 2025

Duas aplicações web com camada de cache dupla (Nginx + Redis), reverse proxy e stack de observabilidade — tudo em um único comando.

## Stack

| Componente | Tecnologia |
|------------|------------|
| App 1 | Python 3.12 + Flask + Gunicorn |
| App 2 | Node.js 20 + Express |
| Cache HTTP | Nginx `proxy_cache` |
| Cache de App | Redis 7 |
| Métricas | Prometheus + Grafana |
| Exporters | redis_exporter, nginx-prometheus-exporter |

## Como rodar

```bash
# Clonar o repositório
git clone <repo-url>
cd devops-challenge-2025

# Subir tudo
docker compose up -d --build

# Verificar containers
docker compose ps
```

Pronto. Um único comando sobe toda a infra.

## Endpoints

| URL | Descrição |
|-----|-----------|
| `http://localhost:8080/app1/` | App1 — texto fixo |
| `http://localhost:8080/app1/time` | App1 — horário do servidor |
| `http://localhost:8080/app2/` | App2 — texto fixo |
| `http://localhost:8080/app2/time` | App2 — horário do servidor |
| `http://localhost:9090` | Prometheus |
| `http://localhost:3001` | Grafana (admin/admin) |

## Cache

O header `X-Cache-Status` nas respostas indica o estado do cache Nginx:

- `MISS` — primeira requisição, buscou no backend
- `HIT`  — servido do cache Nginx
- `EXPIRED` — cache expirado, buscou novamente

Já o campo `"cached": true/false` no JSON indica o estado do cache Redis (L2).

### TTLs

| App | Cache Nginx | Cache Redis |
|-----|------------|-------------|
| App1 (Python) | **10 segundos** | **10 segundos** |
| App2 (Node) | **60 segundos** | **60 segundos** |

## Testando o cache

```bash
# App1 — deve mostrar HIT após primeira requisição (cache 10s)
curl -I http://localhost:8080/app1/time

# App2 — cache de 1 minuto
curl -I http://localhost:8080/app2/time

# Verificar o header de cache
curl -sv http://localhost:8080/app1/ 2>&1 | grep X-Cache-Status
```

## Observabilidade

Acesse o Grafana em `http://localhost:3001` com `admin/admin`.

O datasource do Prometheus já vem pré-configurado. Importe dashboards da comunidade:

- **Redis**: ID `763`
- **Nginx**: ID `12708`
- **Node.js**: ID `11159`

## Estrutura do projeto

```
devops-challenge-2025/
├── app1-python/
│   ├── app.py
│   ├── requirements.txt
│   └── Dockerfile
├── app2-node/
│   ├── index.js
│   ├── package.json
│   └── Dockerfile
├── nginx/
│   └── nginx.conf
├── monitoring/
│   ├── prometheus.yml
│   └── grafana/
│       └── datasources/
│           └── prometheus.yml
├── docs/
│   └── architecture.md   ← diagrama + análise + melhorias
└── docker-compose.yml
```

## Parar a infra

```bash
docker compose down
# Para remover volumes também:
docker compose down -v
```

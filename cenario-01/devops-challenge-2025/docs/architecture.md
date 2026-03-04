# Arquitetura — DevOps Challenge 2025

## Diagrama

```
                        ┌─────────────────────────────────────────────────┐
                        │                  Docker Network                  │
                        │                                                  │
  Usuário               │   ┌──────────────────────────────────────────┐  │
  (Browser/CLI)  ──────►│   │            NGINX (porta 8080)            │  │
                        │   │       Reverse Proxy + HTTP Cache          │  │
                        │   │                                          │  │
                        │   │  /app1/*  → cache 10s (proxy_cache)      │  │
                        │   │  /app2/*  → cache 60s (proxy_cache)      │  │
                        │   └───────────────┬──────────────────┬───────┘  │
                        │                   │                  │           │
                        │          ┌────────▼───────┐ ┌───────▼────────┐  │
                        │          │  App1 (Python) │ │  App2 (Node)   │  │
                        │          │  Flask :5000   │ │  Express :3000 │  │
                        │          │                │ │                │  │
                        │          │  GET /         │ │  GET /         │  │
                        │          │  GET /time     │ │  GET /time     │  │
                        │          │  GET /metrics  │ │  GET /metrics  │  │
                        │          └────────┬───────┘ └───────┬────────┘  │
                        │                   │                  │           │
                        │                   └────────┬─────────┘           │
                        │                            │                     │
                        │                   ┌────────▼───────┐             │
                        │                   │  Redis :6379   │             │
                        │                   │  App Cache     │             │
                        │                   │  App1 TTL=10s  │             │
                        │                   │  App2 TTL=60s  │             │
                        │                   └────────────────┘             │
                        │                                                  │
                        │   ┌──────────────────────────────────────────┐  │
                        │   │              Observabilidade              │  │
                        │   │                                          │  │
                        │   │  Prometheus :9090  ◄── scrape metrics    │  │
                        │   │  Grafana :3001     ◄── dashboards        │  │
                        │   │  redis-exporter    ── expõe Redis stats  │  │
                        │   │  nginx-exporter    ── expõe Nginx stats  │  │
                        │   └──────────────────────────────────────────┘  │
                        └─────────────────────────────────────────────────┘
```

---

## Camadas de Cache

| Camada | Onde | TTL App1 | TTL App2 | Mecanismo |
|--------|------|----------|----------|-----------|
| L1 — HTTP | Nginx | 10 segundos | 60 segundos | `proxy_cache` |
| L2 — App | Redis | 10 segundos | 60 segundos | `SETEX` via SDK |

A dupla camada garante:
- **Nginx** serve respostas sem nem chegar nas apps (máxima performance).
- **Redis** protege quando o cache do Nginx expira mas as apps estão sob carga.

---

## Fluxo de Atualização

### Código das Aplicações (CI/CD)

```
Developer  →  git push  →  GitHub Actions  →  Build Docker Image
                                               │
                                      ┌────────▼────────┐
                                      │  Registry (GHCR  │
                                      │  ou Docker Hub)  │
                                      └────────┬────────┘
                                               │
                                      docker compose pull
                                      docker compose up -d --no-deps app1
                                           (rolling update zero-downtime)
```

### Infraestrutura (IaC)

```
Developer  →  git push  →  GitHub Actions  →  Validação (lint/plan)
                                               │
                                      Aprovação manual (PR)
                                               │
                                      Apply automático (main branch)
```

### Redis (sem downtime)

- Qualquer alteração de config → `docker compose up -d redis`
- Dado em cache é volátil por design; apps re-populam automaticamente após restart.

### Nginx

- Atualizar `nginx.conf` → `docker compose exec nginx nginx -s reload` (sem reiniciar o container)

---

## Pontos de Melhoria

### Disponibilidade

| # | Ponto | Sugestão |
|---|-------|----------|
| 1 | Nginx é SPOF | Adicionar segundo Nginx + Keepalived/HAProxy na frente |
| 2 | Redis é SPOF | Redis Sentinel ou Redis Cluster para HA |
| 3 | Apps sem réplicas | Escalar horizontalmente com `deploy.replicas` no Compose ou migrar para Kubernetes |

### Segurança

| # | Ponto | Sugestão |
|---|-------|----------|
| 4 | HTTP puro | Adicionar TLS (Let's Encrypt via Certbot ou Traefik) |
| 5 | Grafana com senha padrão | Gerenciar segredos com Vault ou Docker Secrets |
| 6 | Redis sem auth | Habilitar `requirepass` no Redis e usar variável de ambiente nas apps |

### Performance

| # | Ponto | Sugestão |
|---|-------|----------|
| 7 | Cache por URL genérica | Variar cache key por `$http_accept_language` ou user-agent se necessário |
| 8 | Sem CDN | Em produção, colocar CDN (CloudFront/Cloudflare) na frente do Nginx |

### Observabilidade

| # | Ponto | Sugestão |
|---|-------|----------|
| 9 | Sem tracing distribuído | Adicionar OpenTelemetry + Jaeger/Tempo |
| 10 | Logs sem agregação | Adicionar Loki + Promtail para centralizar logs |
| 11 | Sem alertas | Configurar AlertManager com regras básicas (app down, cache miss alto) |

### CI/CD

| # | Ponto | Sugestão |
|---|-------|----------|
| 12 | Deploy manual | Pipeline completo com GitHub Actions (build → test → push → deploy) |
| 13 | Sem testes | Adicionar testes unitários e de integração no pipeline |
| 14 | Compose em produção | Migrar para Kubernetes (k3s/EKS) para orquestração real |

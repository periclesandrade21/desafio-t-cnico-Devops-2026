# Arquitetura — DevOps Challenge 2025

## Diagrama Completo

```
╔══════════════════════════════════════════════════════════════════════════════════╗
║                           DOCKER NETWORK: devops-net                            ║
║                                                                                  ║
║  ┌─────────────────────────────────────────────────────────────────────────┐    ║
║  │                      PLANO DE PRODUÇÃO (Apps)                           │    ║
║  │                                                                         │    ║
║  │  Usuário ──────► NGINX :8080 ──┬──► App1 (Python/Flask :5000)          │    ║
║  │  (browser)       [L1 Cache]    │     [L2 Cache Redis: 10s]              │    ║
║  │                  App1: 10s     └──► App2 (Node/Express :3000)           │    ║
║  │                  App2: 60s           [L2 Cache Redis: 60s]              │    ║
║  │                        ↕                                                │    ║
║  │                     Redis :6379                                         │    ║
║  └─────────────────────────────────────────────────────────────────────────┘    ║
║                                                                                  ║
║  ┌─────────────────────────────────────────────────────────────────────────┐    ║
║  │                    PLANO DE OBSERVABILIDADE                             │    ║
║  │                                                                         │    ║
║  │  Prometheus :9090 ◄── scrape ── App1 /metrics                          │    ║
║  │        │                    ── App2 /metrics                            │    ║
║  │        │                    ── redis-exporter :9121                     │    ║
║  │        │                    ── nginx-exporter :9113                     │    ║
║  │        ▼                                                                │    ║
║  │  Grafana :3001 (dashboards)                                             │    ║
║  └─────────────────────────────────────────────────────────────────────────┘    ║
║                                                                                  ║
║  ┌─────────────────────────────────────────────────────────────────────────┐    ║
║  │                    PLANO DE CI/CD                                       │    ║
║  │                                                                         │    ║
║  │  git push / poll                                                        │    ║
║  │       │                                                                 │    ║
║  │       ▼                                                                 │    ║
║  │  Jenkins :8088 ──── Pipeline ──────────────────────────────────────►   │    ║
║  │       │                                                                 │    ║
║  │       ├──► SAST: SonarQube :9000 ◄── PostgreSQL :5432                  │    ║
║  │       │         (Code Quality + Security Hotspots)                     │    ║
║  │       │                                                                 │    ║
║  │       ├──► SAST: OWASP Dependency-Check                                │    ║
║  │       │         (CVEs em dependências)                                  │    ║
║  │       │                                                                 │    ║
║  │       ├──► Build Docker Images                                          │    ║
║  │       │                                                                 │    ║
║  │       ├──► Push ──► Artifactory :8082 (Docker Registry :5002)          │    ║
║  │       │             (Imagens Docker versionadas)                        │    ║
║  │       │                                                                 │    ║
║  │       ├──► Publish ► Nexus :8081                                        │    ║
║  │       │             (npm proxy / PyPI proxy / raw-artifacts)            │    ║
║  │       │                                                                 │    ║
║  │       ├──► Deploy: docker compose up -d (apps)                         │    ║
║  │       │                                                                 │    ║
║  │       └──► DAST: OWASP ZAP ──► http://nginx/app1/                      │    ║
║  │                                http://nginx/app2/                      │    ║
║  │                                                                         │    ║
║  └─────────────────────────────────────────────────────────────────────────┘    ║
║                                                                                  ║
╚══════════════════════════════════════════════════════════════════════════════════╝
```

---

## Responsabilidade de Cada Serviço

| Serviço | Papel | Porta |
|---------|-------|-------|
| App1 (Flask) | API Python — texto fixo + horário | 5000 (interno) |
| App2 (Express) | API Node.js — texto fixo + horário | 3000 (interno) |
| Redis | Cache L2 (app-level) | 6379 (interno) |
| Nginx | Reverse proxy + Cache L1 (HTTP) | 8080 |
| Jenkins | Orquestrador do pipeline CI/CD | 8088 |
| SonarQube | SAST — qualidade e segurança de código | 9000 |
| PostgreSQL | Banco de dados do SonarQube | 5432 (interno) |
| Nexus | npm proxy, PyPI proxy, raw artifacts | 8081 |
| Artifactory | Docker registry + relatórios segurança | 8082 / 5002 |
| Prometheus | Coleta de métricas | 9090 |
| Grafana | Dashboards de observabilidade | 3001 |
| OWASP ZAP | DAST — scan dinâmico das apps em execução | ephemeral |

---

## Camadas de Cache

| Camada | Serviço | TTL App1 | TTL App2 |
|--------|---------|----------|----------|
| L1 HTTP | Nginx proxy_cache | **10 s** | **60 s** |
| L2 App | Redis SETEX | **10 s** | **60 s** |

---

## Fluxo de CI/CD (Pipeline Jenkins)

```
 git push / pollSCM (5 min)
          │
          ▼
 ┌─────────────────┐
 │  1. Checkout    │  git clone file:///project
 └────────┬────────┘
          │
          ▼
 ┌─────────────────────────────────────────────┐
 │  2. SAST — SonarQube (paralelo app1+app2)   │
 │     • Code smells, bugs, vulnerabilidades   │
 │     • Security Hotspots                     │
 └────────┬────────────────────────────────────┘
          │
          ▼
 ┌────────────────────────┐
 │  3. Quality Gate       │  Aguarda resultado SonarQube
 └────────┬───────────────┘
          │
          ▼
 ┌─────────────────────────────────────────────┐
 │  4. SAST — Dependency Check (paralelo)      │
 │     • CVEs em requirements.txt/package.json │
 │     • CVSS ≥ 9 → falha o build             │
 └────────┬────────────────────────────────────┘
          │
          ▼
 ┌────────────────────────────┐
 │  5. Build Docker Images    │  docker build app1 + app2
 └────────┬───────────────────┘
          │
          ▼
 ┌─────────────────────────────────────┐
 │  6. Push → Artifactory (Docker)     │  :5002/devops-challenge/app1:N
 └────────┬────────────────────────────┘
          │
          ▼
 ┌───────────────────────────────────────┐
 │  7. Publish → Nexus (raw artifacts)   │  requirements.txt, package.json
 └────────┬──────────────────────────────┘
          │
          ▼
 ┌──────────────────────────────┐
 │  8. Deploy — docker compose  │  Atualiza app1, app2, nginx
 └────────┬─────────────────────┘
          │
          ▼
 ┌──────────────────────────────────────────────────┐
 │  9. DAST — OWASP ZAP (paralelo app1 + app2)     │
 │     • Baseline scan nas rotas públicas           │
 │     • Verifica OWASP Top 10                      │
 └────────┬─────────────────────────────────────────┘
          │
          ▼
 ┌──────────────────────────────────────────────────┐
 │  10. Publish Reports                             │
 │      • Relatórios ZAP → Nexus raw-artifacts      │
 │      • DepCheck reports → Artifactory            │
 │      • HTML reports → Jenkins UI                 │
 └──────────────────────────────────────────────────┘
```

---

## Fluxo de Atualização

### Código das Aplicações

```
Developer → git commit → git push (ou polling 5 min)
                │
                ▼
         Jenkins detecta mudança
                │
         Pipeline roda automaticamente
                │
         ┌──── SAST pass? ────┐
         │ Sim                │ Não
         ▼                    ▼
     Build + Push       Notifica + Falha
         │
     Deploy atualizado
         │
     DAST valida apps ao vivo
```

### Infraestrutura (IaC)

```
Developer → edita docker-compose*.yml / nginx.conf / casc.yaml
          → git commit + push
          → Pipeline detecta + re-executa
          → make clean && make all (em caso de mudanças estruturais)
```

### Atualização sem downtime

- **Nginx**: `docker compose exec nginx nginx -s reload` (sem restart)
- **Redis**: config hot-reload via `CONFIG SET`
- **Apps**: `docker compose up -d --no-deps app1 app2` (rolling update)
- **Jenkins config**: editar `casc.yaml` + `Manage Jenkins > Reload JCasC`

---

## Pontos de Melhoria

### Alta Disponibilidade

| # | Problema atual | Solução sugerida |
|---|----------------|-----------------|
| 1 | Nginx SPOF | HAProxy + 2× Nginx / Traefik com réplicas |
| 2 | Redis sem HA | Redis Sentinel (3 nós) ou Redis Cluster |
| 3 | Jenkins SPOF | Jenkins ativo/ativo com agentes remotos ou migrar para GitLab CI (nativo HA) |
| 4 | Apps sem réplica | Escalar com `deploy.replicas: 3` no Compose ou migrar para Kubernetes |

### Segurança

| # | Problema atual | Solução sugerida |
|---|----------------|-----------------|
| 5 | HTTP puro | TLS via Traefik + Let's Encrypt automático |
| 6 | Senhas em .env versionado | HashiCorp Vault / AWS Secrets Manager / Docker Secrets |
| 7 | Redis sem auth | `requirepass` + `ACL` para usuários separados |
| 8 | DAST só baseline | ZAP Full Scan + ZAP API Scan com OpenAPI spec |
| 9 | Imagens sem scan | Trivy / Grype no pipeline (Container Image Scanning) |
| 10 | SonarQube sem branch analysis | SonarQube Developer Edition para análise de PRs |

### Pipeline & CI/CD

| # | Problema atual | Solução sugerida |
|---|----------------|-----------------|
| 11 | Git local (file://) | Gitea self-hosted ou GitHub/GitLab externo |
| 12 | Deploy via compose | Helm + Kubernetes (Argo CD para GitOps) |
| 13 | Sem testes automatizados | Pytest (app1) + Jest (app2) com coverage no pipeline |
| 14 | Sem notificações | Slack webhook / e-mail no post { failure } do Jenkinsfile |
| 15 | DAST sem autenticação | ZAP + script de autenticação para rotas protegidas |

### Observabilidade

| # | Problema atual | Solução sugerida |
|---|----------------|-----------------|
| 16 | Logs sem agregação | Loki + Promtail ou ELK Stack |
| 17 | Sem tracing distribuído | OpenTelemetry → Jaeger ou Grafana Tempo |
| 18 | Sem alertas | AlertManager com regras de SLO/SLA |
| 19 | Métricas de pipeline ausentes | Jenkins prometheus plugin + dashboard Grafana #9964 |

### Performance

| # | Problema atual | Solução sugerida |
|---|----------------|-----------------|
| 20 | Cache sem invalidação inteligente | Cache por versão de release (tagged cache keys) |
| 21 | Sem CDN | Cloudflare / CloudFront na frente do Nginx |
| 22 | Build sem cache de camadas | Buildkit cache + registry cache para acelerar builds |

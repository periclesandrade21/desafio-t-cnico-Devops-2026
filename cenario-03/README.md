# DevOps Challenge 2026 

Stack completa com HTTPS automático, CI/CD, SAST, DAST, repositórios de artefatos, 4 dashboards Grafana e observabilidade — tudo em **um único comando**.

---

##  Como rodar

```bash
git clone <repo-url>
cd devops-challenge-2025
make git-init   # inicializa git local para Jenkins SCM
make all        # sobe tudo
```

Para trustar o certificado TLS self-signed no sistema:
```bash
make trust-cert
```

---

##  HTTPS — Automático e sem configuração

O certificado TLS é gerado automaticamente pelo container `cert-gen` (Alpine + OpenSSL) **antes** do Nginx iniciar:

- Algoritmo: RSA 4096
- Validade: 825 dias
- SAN: `DNS:localhost`, `DNS:devops-challenge.local`, `IP:127.0.0.1`
- Localização (volume Docker): `tls_certs:/certs/`

O Nginx serve **TLS 1.2 + 1.3** com cipher suite moderna e inclui `HSTS`, `X-Content-Type-Options`, `X-Frame-Options` e `Referrer-Policy`.

O HTTP (porta 8080) redireciona automaticamente para HTTPS (porta 8443).

---

##  URLs

| Serviço | HTTP | HTTPS |
|---------|------|-------|
| **App1** (Python) | http://localhost:8080/app1/ → redirect | https://localhost:8443/app1/ |
| **App2** (Node.js) | http://localhost:8080/app2/ → redirect | https://localhost:8443/app2/ |
| Jenkins | http://localhost:8088 | — |
| SonarQube | http://localhost:9000 | — |
| Nexus | http://localhost:8081 | — |
| Artifactory | http://localhost:8082 | — |
| **Grafana** | http://localhost:3001 | — |
| Prometheus | http://localhost:9090 | — |

>  Certificado self-signed: o browser vai mostrar aviso de segurança. Rode `make trust-cert` ou aceite a exceção manualmente.

---

##  Dashboards Grafana

Acesse **http://localhost:3001** (admin / admin). Os 4 dashboards são provisionados automaticamente na pasta **DevOps Challenge 2025**:

| Dashboard | O que monitora |
|-----------|---------------|
| **Apps Overview** | Req/s, latência P50/P95/P99, cache Redis hit rate, CPU/RAM App1 e App2 |
| **Redis Cache** | Memória, hit/miss rate, comandos/s, evictions, chaves por DB |
| **Nginx + TLS** | Conexões, throughput, cache L1 HIT/MISS por app (10s vs 60s) |
| **CI/CD & Infraestrutura** | Status UP/DOWN de todos os serviços, uptime 24h, links rápidos |

---

##  Pipeline CI/CD (Jenkins)

```
git push → Checkout → SAST SonarQube (paralelo)
         → Quality Gate → DepCheck (paralelo)
         → Build Docker → Push Artifactory
         → Publish Nexus → Deploy → DAST ZAP (paralelo)
         → Publish Reports
```

Acionamento manual:
```bash
make pipeline
```

---

##  Estrutura

```
devops-challenge-2025/
├── .env                        ← Portas e senhas
├── Makefile                    ← Comandos (make all / make trust-cert)
├── Jenkinsfile                 ← Pipeline declarativo completo
├── docker-compose.yml          ← Apps + Nginx TLS + Observabilidade
├── docker-compose.ci.yml       ← Jenkins, SonarQube, Nexus, Artifactory
├── app1-python/                ← Flask + PrometheusMetrics
├── app2-node/                  ← Express + prom-client
├── nginx/
│   ├── nginx.conf              ← HTTP→HTTPS redirect + TLS + cache
│   └── certs/gen-certs.sh      ← Geração automática de cert (openssl)
├── ci/
│   ├── jenkins/
│   │   ├── Dockerfile          ← Jenkins + sonar-scanner + dep-check
│   │   ├── plugins.txt
│   │   └── casc.yaml           ← Auto-configuração Jenkins (JCasC)
│   └── scripts/
│       ├── Dockerfile.init
│       └── init-services.sh    ← Configura SonarQube, Nexus, Artifactory
├── monitoring/
│   ├── prometheus.yml
│   └── grafana/
│       ├── datasources/prometheus.yml
│       └── dashboards/
│           ├── dashboards.yml       ← Provisioning config
│           ├── apps-overview.json   ← Dashboard: Apps
│           ├── redis.json           ← Dashboard: Redis
│           ├── nginx.json           ← Dashboard: Nginx + TLS
│           └── cicd.json            ← Dashboard: CI/CD status
└── docs/architecture.md        ← Diagrama + análise + 22 melhorias
```

---

##  Parar / Limpar

```bash
make down    # para tudo (mantém volumes)
make clean   # reset total (remove volumes e rede)
```

# Desafio-tecnico-Devops-2026

Este repositório documenta a evolução de uma infraestrutura DevOps construída em três cenários progressivos — do básico ao Kubernetes com GitOps.

---

##  Cenário 1 — Aplicações com Cache e Observabilidade

### O que foi construído

Duas aplicações web em linguagens diferentes, expostas por um proxy reverso com cache em dois níveis e uma stack de observabilidade completa.

**Aplicações**

| App | Tecnologia | Rota texto | Rota horário |
|-----|-----------|------------|--------------|
| App1 | Python 3.12 + Flask | `GET /` | `GET /time` |
| App2 | Node.js 20 + Express | `GET /` | `GET /time` |

**Camadas de Cache**

| Nível | Onde | App1 TTL | App2 TTL |
|-------|------|----------|----------|
| L1 — HTTP | Nginx `proxy_cache` | **10 s** | **60 s** |
| L2 — App | Redis `SETEX` | **10 s** | **60 s** |

O header `X-Cache-Status: HIT/MISS` nas respostas indica o estado do cache Nginx. O campo `"cached": true/false` no JSON indica o estado do cache Redis.

**Observabilidade**

- Prometheus coletando métricas das apps, Redis e Nginx
- Grafana com 4 dashboards provisionados automaticamente: Apps Overview, Redis Cache, Nginx + TLS, CI/CD & Infraestrutura
- `redis_exporter` e `nginx-prometheus-exporter` como sidecars de métricas

**HTTPS automático**

Um container `cert-gen` (Alpine + OpenSSL RSA 4096) gera o certificado TLS antes do Nginx subir. HTTP na porta 8080 redireciona para HTTPS na porta 8443. Nginx configurado com TLS 1.2/1.3, HSTS e security headers.

**Como rodar**

```bash
git clone <repo>
cd devops-challenge-2025
make up           # sobe apps + cache + observabilidade
```

**URLs**

| Serviço | Endereço |
|---------|---------|
| App1 | https://localhost:8443/app1/ |
| App2 | https://localhost:8443/app2/ |
| Grafana | http://localhost:3001 (admin/admin) |
| Prometheus | http://localhost:9090 |

---

##  Cenário 2 — CI/CD Completo com SAST, DAST e Repositórios

### O que foi construído

Uma pipeline de CI/CD completa integrada ao Jenkins, sem nenhuma configuração manual. Basta executar `make all`.

**Serviços de CI/CD**

| Serviço | Papel | Porta |
|---------|-------|-------|
| Jenkins LTS | Orquestrador do pipeline | 8088 |
| SonarQube 10 | SAST — qualidade e segurança de código | 9000 |
| OWASP Dependency-Check | SAST — CVEs em dependências | (embutido no Jenkins) |
| OWASP ZAP | DAST — scan dinâmico das apps em execução | (container efêmero) |
| JFrog Artifactory OSS | Docker Registry de imagens | 8082 / 5002 |
| Sonatype Nexus 3 | Proxy npm/PyPI + artefatos raw | 8081 |

**Automação zero-touch**

Um container `init-services` (Alpine + bash + curl) roda antes do Jenkins e configura automaticamente SonarQube (senha, projetos, token de análise), Nexus (repositórios npm proxy, PyPI proxy, docker-hosted, raw-artifacts) e Artifactory (repositórios docker-local e security-reports). O Jenkins lê os segredos gerados via JCasC (`casc.yaml`) e se auto-configura sem intervenção humana.

**Pipeline Jenkins (10 estágios)**

```
Checkout
  ↓
SAST SonarQube (app1 + app2 em paralelo)
  ↓
Quality Gate (aguarda resultado SonarQube)
  ↓
SAST Dependency Check (app1 + app2 em paralelo)
  ↓
Build Docker Images (app1 + app2 em paralelo)
  ↓
Push → Artifactory (Docker Registry)
  ↓
Publish → Nexus (artefatos versionados)
  ↓
Deploy (docker compose up)
  ↓
DAST ZAP (app1 + app2 em paralelo)
  ↓
Publish Reports (Nexus + Artifactory + Jenkins UI)
```

O pipeline é acionado por polling a cada 5 minutos ou `make pipeline` para acionar manualmente via API.

**Como rodar**

```bash
make git-init     # inicializa git local para o Jenkins SCM
make all          # sobe apps + CI/CD completo
```

>  SonarQube e Artifactory levam ~2–3 min para iniciar. Jenkins sobe somente depois que todos os serviços estão prontos e configurados.

**URLs adicionais**

| Serviço | Endereço | Credenciais |
|---------|---------|-------------|
| Jenkins | http://localhost:8088 | admin / admin123 |
| SonarQube | http://localhost:9000 | admin / admin123 |
| Nexus | http://localhost:8081 | admin / admin123 |
| Artifactory | http://localhost:8082 | admin / password |

---

##  Cenário 3 — Kubernetes (K3s) com GitOps e Alta Disponibilidade

### O que foi construído

Migração da infraestrutura para Kubernetes (K3s) com GitOps via ArgoCD, eliminando os pontos únicos de falha e adicionando escalonamento automático, tracing distribuído e agregação de logs.

**Instalação automatizada**

```bash
sudo bash scripts/install-k3s.sh
```

O script instala e configura em sequência: K3s, Helm, cert-manager, Traefik (Ingress Controller), ArgoCD com CLI e, por fim, aplica todos os manifests Kubernetes. Não é necessária nenhuma etapa manual.

**Alta Disponibilidade — pontos de falha eliminados**

| Componente anterior | Problema | Solução K3s |
|--------------------|----------|-------------|
| Nginx (1 instância) | SPOF | **HAProxy com 2 réplicas** + `podAntiAffinity` em nós diferentes |
| Redis (standalone) | SPOF | **Redis Sentinel** StatefulSet (1 master + 2 replicas, failover automático) |
| Apps (1 container) | Sem redundância | **2 réplicas mínimas** + HPA escalando até 8 pods |

**GitOps com ArgoCD**

Cada componente tem uma `Application` ArgoCD que monitora o repositório Git. Com `selfHeal: true`, qualquer desvio de configuração é corrigido automaticamente. Com `prune: true`, recursos removidos do Git são deletados do cluster. O HPA é protegido via `ignoreDifferences` para não ser sobrescrito a cada sync.

```
git commit + push
      ↓
ArgoCD detecta mudança (polling 3 min)
      ↓
Sync automático → kubectl apply
      ↓
Rolling update zero-downtime
      ↓
selfHeal monitora continuamente
```

**Jenkins + K3s**

O Jenkinsfile detecta se K3s está disponível. Se sim, atualiza a imagem via `kubectl set image` e força sync no ArgoCD. Se não, faz fallback para `docker compose up` automaticamente.

**Observabilidade ampliada**

| Novo componente | Função |
|----------------|--------|
| Loki + Promtail (DaemonSet) | Agregação de logs de todos os pods |
| Jaeger All-in-One | Tracing distribuído via OTLP |
| OTel Collector | Recebe traces/métricas das apps e roteia para Jaeger e Prometheus |
| AlertManager | 12 regras de alerta (AppDown, CrashLoop, RedisMissHigh, MemoryHigh, NodeNotReady…) |

**Requisitos de hardware**

| Cenário | RAM | CPU | Disco |
|---------|-----|-----|-------|
| Mínimo (1 nó) | 8 GB | 4 cores | 60 GB |
| Recomendado (1 nó) | **16 GB** | **8 cores** | **120 GB SSD** |
| Produção (3 nós) | 32 GB total | 12 cores total | 200 GB total |

Veja o detalhamento completo por componente — incluindo `requests`, `limits` e equivalências em instâncias AWS/GCP/Azure — em [`docs/resource-requirements.md`](docs/resource-requirements.md).

**URLs K3s**

| Serviço | Endereço |
|---------|---------|
| App1 | https://app1.devops.local:30443 |
| App2 | https://app2.devops.local:30443 |
| HAProxy Stats | http://localhost:30404/stats |
| ArgoCD | http://localhost:30080 |
| Jaeger UI | http://localhost:30686 |
| AlertManager | http://localhost:30093 |

```bash
# Adicionar ao /etc/hosts para usar os domínios
127.0.0.1  app1.devops.local app2.devops.local argocd.devops.local
```

**Comandos úteis**

```bash
make k3s-status      # status de todos os pods
make k3s-sync        # sync manual ArgoCD
make k3s-resources   # uso de CPU/RAM pelo cluster
make k3s-logs APP=app1  # logs em tempo real
make k3s-rollback APP=app1-python  # rollback de release
```

---

## Estrutura do Repositório

```
devops-challenge-2025/
├── app1-python/            # Flask app
├── app2-node/              # Express app
├── nginx/                  # Proxy reverso + TLS auto
├── ci/
│   ├── jenkins/            # Dockerfile + JCasC (casc.yaml)
│   └── scripts/            # init-services.sh (zero-touch setup)
├── k8s/
│   ├── apps/               # Deployments, Services, HPA
│   ├── redis/              # Redis Sentinel StatefulSet
│   ├── haproxy/            # HAProxy HA
│   ├── ingress/            # Traefik + cert-manager
│   ├── monitoring/         # AlertManager, Loki, Promtail, Jaeger, OTel
│   └── argocd/             # Applications + AppProject GitOps
├── monitoring/
│   └── grafana/dashboards/ # 4 dashboards JSON (provisionados automaticamente)
├── scripts/
│   └── install-k3s.sh      # Instalação completa K3s + ArgoCD
├── docs/
│   ├── architecture.md     # Diagrama + 22 pontos de melhoria
│   └── resource-requirements.md  # Calculadora de recursos
├── docker-compose.yml      # Apps + Observabilidade
├── docker-compose.ci.yml   # Jenkins + SonarQube + Nexus + Artifactory
├── Jenkinsfile             # Pipeline completo (SAST → DAST → K3s deploy)
└── Makefile                # Todos os comandos
```

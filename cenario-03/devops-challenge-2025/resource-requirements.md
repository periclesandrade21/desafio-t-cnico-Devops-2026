# Calculadora de Recursos — DevOps Challenge 2025

> Estimativas baseadas em cargas típicas de desenvolvimento/staging.
> Para produção com tráfego real, multiplicar os valores de "Recomendado" por 1.5–2×.

---

## Sumário Executivo

| Cenário | RAM | CPU | Disco | Nós K3s |
|---------|-----|-----|-------|---------|
| **Mínimo (1 nó)** | 8 GB | 4 cores | 60 GB | 1 (all-in-one) |
| **Recomendado (1 nó)** | 16 GB | 8 cores | 120 GB | 1 (all-in-one) |
| **Produção (3 nós)** | 32 GB total | 12 cores total | 200 GB total | 3 (1 control-plane + 2 workers) |
| **Alta escala** | 64 GB total | 24 cores total | 400 GB total | 5+ nós |

---

## Detalhamento por Componente

### 🌐 Aplicações (Namespace: `devops-challenge`)

| Componente | Réplicas | RAM Req | RAM Limit | CPU Req | CPU Limit | RAM Total | CPU Total |
|-----------|----------|---------|-----------|---------|-----------|-----------|-----------|
| App1 (Python/Flask) | 2 | 64 Mi | 256 Mi | 50m | 250m | **128–512 Mi** | **100–500m** |
| App2 (Node.js/Express) | 2 | 64 Mi | 256 Mi | 50m | 250m | **128–512 Mi** | **100–500m** |
| Redis (StatefulSet) | 3 | 64 Mi | 192 Mi | 50m | 200m | **192–576 Mi** | **150–600m** |
| Redis Sentinel (sidecar) | 3 | 32 Mi | 64 Mi | 20m | 100m | **96–192 Mi** | **60–300m** |
| Redis Exporter (sidecar) | 3 | 16 Mi | 32 Mi | 10m | 50m | **48–96 Mi** | **30–150m** |
| HAProxy | 2 | 32 Mi | 128 Mi | 50m | 500m | **64–256 Mi** | **100–1000m** |
| **Subtotal Apps** | | | | | | **~660 Mi–2.1 Gi** | **~540m–3.05 cores** |

### 🔧 CI/CD (Docker Compose — separado do K3s)

| Componente | RAM Mín | RAM Ideal | CPU Mín | CPU Ideal | Disco |
|-----------|---------|-----------|---------|-----------|-------|
| Jenkins (LTS + plugins) | 1 Gi | 2 Gi | 500m | 1 core | 10 GB |
| SonarQube 10 Community | 2 Gi | 3 Gi | 500m | 1 core | 5 GB |
| PostgreSQL (SonarQube) | 256 Mi | 512 Mi | 100m | 500m | 5 GB |
| Nexus 3 | 1 Gi | 2 Gi | 500m | 1 core | 20 GB |
| Artifactory OSS | 1 Gi | 2 Gi | 500m | 1 core | 20 GB |
| **Subtotal CI/CD** | **~5.2 Gi** | **~9.5 Gi** | **~2.1 cores** | **~4.5 cores** | **~60 GB** |

> ⚠️ SonarQube requer `vm.max_map_count=524288` no host — verificado no script de instalação.

### 📊 Observabilidade (Namespace: `monitoring`)

| Componente | RAM Req | RAM Limit | CPU Req | CPU Limit | Disco PVC |
|-----------|---------|-----------|---------|-----------|-----------|
| Prometheus | 256 Mi | 512 Mi | 100m | 500m | 5 GB |
| Grafana | 128 Mi | 256 Mi | 50m | 200m | 1 GB |
| AlertManager | 32 Mi | 128 Mi | 20m | 100m | — |
| Loki (StatefulSet) | 128 Mi | 512 Mi | 50m | 500m | 5 GB |
| Promtail (DaemonSet × nós) | 32 Mi/nó | 128 Mi/nó | 20m/nó | 200m/nó | — |
| Jaeger All-in-One | 128 Mi | 512 Mi | 50m | 500m | — |
| OTel Collector | 64 Mi | 256 Mi | 30m | 300m | — |
| Redis Exporter | 16 Mi | 32 Mi | 10m | 50m | — |
| Nginx Exporter | 16 Mi | 32 Mi | 10m | 50m | — |
| **Subtotal Observabilidade** | **~800 Mi** | **~2.3 Gi** | **~340m** | **~2.4 cores** | **~11 GB** |

### 🚀 K3s + GitOps

| Componente | RAM Req | RAM Limit | CPU Req | CPU Limit | Disco |
|-----------|---------|-----------|---------|-----------|-------|
| K3s (control-plane) | 512 Mi | 1 Gi | 250m | 1 core | 5 GB |
| ArgoCD (5 pods) | 512 Mi | 1 Gi | 250m | 500m | 1 GB |
| cert-manager (3 pods) | 64 Mi | 128 Mi | 50m | 200m | — |
| Traefik (Ingress) | 64 Mi | 256 Mi | 50m | 300m | — |
| **Subtotal K3s + GitOps** | **~1.1 Gi** | **~2.4 Gi** | **~600m** | **~2 cores** | **~6 GB** |

---

## Totais Consolidados

### Configuração Mínima (1 servidor, todas as cargas)

```
┌────────────────────────────────────────────────────────────────┐
│  CONFIGURAÇÃO MÍNIMA — 1 servidor                              │
├────────────────┬───────────────┬─────────────┬─────────────────┤
│ Categoria      │ RAM           │ CPU         │ Disco           │
├────────────────┼───────────────┼─────────────┼─────────────────┤
│ Apps (K3s)     │  660 Mi       │   540m      │  5 GB (PVCs)    │
│ CI/CD (Compose)│    5.2 Gi     │   2.1 cores │ 60 GB           │
│ Observabilidade│  800 Mi       │   340m      │ 11 GB (PVCs)    │
│ K3s + GitOps   │    1.1 Gi     │   600m      │  6 GB           │
│ Sistema OS     │    1.0 Gi     │   500m      │ 10 GB           │
├────────────────┼───────────────┼─────────────┼─────────────────┤
│ TOTAL MÍNIMO   │  ~9 Gi        │ ~4.1 cores  │ ~92 GB          │
│ RECOMENDADO    │  16 Gi        │  8 cores    │ 120 GB SSD      │
└────────────────┴───────────────┴─────────────┴─────────────────┘
```

### Configuração Recomendada (Produção — 3 nós)

```
┌─────────────────────────────────────────────────────────────────────┐
│  CONFIGURAÇÃO PRODUÇÃO — 3 nós K3s + 1 servidor CI/CD              │
├──────────────────┬─────────────┬────────────┬──────────────────────┤
│ Servidor         │ RAM         │ CPU        │ Disco                │
├──────────────────┼─────────────┼────────────┼──────────────────────┤
│ K3s Control-Plane│  8 GB       │ 4 cores    │  60 GB SSD           │
│ K3s Worker 1     │  8 GB       │ 4 cores    │  60 GB SSD           │
│ K3s Worker 2     │  8 GB       │ 4 cores    │  60 GB SSD           │
│ CI/CD Server     │ 16 GB       │ 8 cores    │ 200 GB SSD           │
├──────────────────┼─────────────┼────────────┼──────────────────────┤
│ TOTAL            │ 40 GB       │ 20 cores   │ 380 GB               │
└──────────────────┴─────────────┴────────────┴──────────────────────┘
```

### Cloud Equivalência (AWS / GCP / Azure)

| Provedor | Instância | vCPU | RAM | Disco | Preço ~USD/mês* |
|----------|-----------|------|-----|-------|----------------|
| **AWS** | t3.xlarge | 4 | 16 GB | 120 GB gp3 | ~$175 |
| **AWS** | m5.2xlarge | 8 | 32 GB | 200 GB gp3 | ~$480 |
| **GCP** | n2-standard-4 | 4 | 16 GB | 120 GB SSD | ~$190 |
| **GCP** | n2-standard-8 | 8 | 32 GB | 200 GB SSD | ~$490 |
| **Azure** | D4s_v3 | 4 | 16 GB | 120 GB Premium SSD | ~$200 |
| **Azure** | D8s_v3 | 8 | 32 GB | 200 GB Premium SSD | ~$520 |

> *Preços aproximados, on-demand, us-east-1 / us-central1, sem commit. Spot/preemptible pode reduzir em 60-70%.

---

## Requisitos do Sistema Operacional Host

### Kernel / OS
```bash
# SonarQube exige vm.max_map_count alto
sysctl -w vm.max_map_count=524288
echo 'vm.max_map_count=524288' >> /etc/sysctl.d/99-devops.conf

# Aumentar limite de arquivos abertos (Redis, Jenkins)
ulimit -n 65536
echo '* soft nofile 65536' >> /etc/security/limits.conf
echo '* hard nofile 65536' >> /etc/security/limits.conf

# Habilitar IP forwarding (K3s)
sysctl -w net.ipv4.ip_forward=1
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.d/99-devops.conf
```

### Dependências obrigatórias
| Ferramenta | Versão Mín | Instalação |
|-----------|-----------|-----------|
| Docker | 24+ | `curl -fsSL https://get.docker.com | sh` |
| Docker Compose | v2.20+ | incluído no Docker |
| git | 2.34+ | `apt install git` / `yum install git` |
| curl | qualquer | pré-instalado |
| make | qualquer | `apt install make` |

### Dependências instaladas automaticamente
| Ferramenta | Instalado por |
|-----------|--------------|
| K3s | `scripts/install-k3s.sh` |
| kubectl | `scripts/install-k3s.sh` (symlink k3s) |
| Helm | `scripts/install-k3s.sh` |
| ArgoCD CLI | `scripts/install-k3s.sh` |
| SonarScanner CLI | `ci/jenkins/Dockerfile` |
| OWASP Dep-Check | `ci/jenkins/Dockerfile` |

---

## Checklist de Capacidade

```
Antes de rodar make all:

[ ] Memória RAM disponível:        ≥ 8 GB  (16 GB recomendado)
[ ] Núcleos de CPU disponíveis:    ≥ 4     (8 recomendado)
[ ] Espaço em disco livre:         ≥ 60 GB (120 GB recomendado, SSD)
[ ] Docker instalado e rodando:    docker info
[ ] Docker Compose v2:             docker compose version
[ ] Git inicializado:              make git-init
[ ] vm.max_map_count ≥ 524288:     cat /proc/sys/vm/max_map_count
[ ] IP forwarding habilitado:      cat /proc/sys/net/ipv4/ip_forward
[ ] Portas livres: 8080, 8443, 8081, 8082, 8088, 9000, 9090, 3001,
                   30000-30443, 6443 (K3s API)
```

---

## HPA — Escalonamento Automático

Com o HPA configurado, os pods escalam automaticamente:

| App | Mín | Máx | Trigger Scale-Up | Trigger Scale-Down |
|-----|-----|-----|------------------|--------------------|
| App1 | 2 | 8 | CPU > 70% ou RAM > 80% | Estável por 5 min |
| App2 | 2 | 8 | CPU > 70% ou RAM > 80% | Estável por 5 min |

**Pico de capacidade (App1 + App2 em max replicas):**
- RAM total apps: ~4 Gi
- CPU total apps: ~4 cores

Garantir que o cluster K3s tenha headroom suficiente para absorver este pico.

# DevOps Challenge 2025 🚀

Stack completa com CI/CD, SAST, DAST, repositórios de artefatos e observabilidade — tudo em **um único comando**.

## Stack completa

| Categoria | Tecnologia |
|-----------|-----------|
| App 1 | Python 3.12 + Flask + Gunicorn |
| App 2 | Node.js 20 + Express |
| Cache HTTP | Nginx `proxy_cache` (10s / 60s) |
| Cache de App | Redis 7 |
| CI/CD | Jenkins LTS (JCasC auto-configurado) |
| SAST | SonarQube 10 Community + OWASP Dependency-Check |
| DAST | OWASP ZAP (baseline scan) |
| Docker Registry | JFrog Artifactory OSS 7 |
| Artefatos / Proxy | Sonatype Nexus 3 (npm, PyPI, raw) |
| Métricas | Prometheus + Grafana |

---

## 🚦 Como rodar (um único comando)

```bash
# 1. Clonar o repositório
git clone <repo-url>
cd devops-challenge-2025

# 2. Inicializar git local (necessário para Jenkins SCM)
make git-init

# 3. Subir TUDO
make all
```

> ⏳ SonarQube (~2 min) e Artifactory (~3 min) levam mais tempo para iniciar.
> Jenkins só sobe **depois** que todos os serviços estão prontos e configurados.

### Subir só as apps (sem CI/CD)

```bash
make up
```

---

## 🌐 URLs de acesso

| Serviço | URL | Credenciais |
|---------|-----|-------------|
| **App1** (Python) | http://localhost:8080/app1/ | — |
| **App2** (Node.js) | http://localhost:8080/app2/ | — |
| **Jenkins** | http://localhost:8088 | admin / admin123 |
| **SonarQube** | http://localhost:9000 | admin / admin123 |
| **Nexus** | http://localhost:8081 | admin / admin123 |
| **Artifactory** | http://localhost:8082 | admin / password |
| **Grafana** | http://localhost:3001 | admin / admin |
| **Prometheus** | http://localhost:9090 | — |

---

## 🔁 Ciclo do Pipeline CI/CD

```
git push → Jenkins detecta → SAST (SonarQube + DepCheck)
         → Quality Gate → Build Docker → Push Artifactory
         → Publish Nexus → Deploy → DAST (ZAP) → Reports
```

O pipeline é acionado automaticamente a cada push ou a cada **5 minutos** por polling.

Para acionar manualmente:
```bash
make pipeline
```

---

## 🔒 Segurança

### SAST (Static Analysis)
- **SonarQube**: análise de código Python e Node.js — bugs, code smells, security hotspots
- **OWASP Dependency-Check**: CVEs em `requirements.txt` e `package.json`
- Relatórios HTML publicados no Jenkins UI

### DAST (Dynamic Analysis)
- **OWASP ZAP Baseline Scan** contra as apps em execução
- Testa OWASP Top 10 nas rotas `/app1/` e `/app2/`
- Relatórios publicados no Nexus (`raw-artifacts`)

---

## 📦 Repositórios de Artefatos

### Artifactory (Docker Registry)
- `docker-local` — imagens `app1` e `app2` com tag de build
- `security-reports` — relatórios SAST/DAST

### Nexus
- `npm-proxy` — proxy do registry.npmjs.org
- `pypi-proxy` — proxy do PyPI
- `docker-hosted` — registry Docker alternativo
- `raw-artifacts` — artefatos de build e relatórios ZAP

---

## 🗂 Estrutura do projeto

```
devops-challenge-2025/
├── .env                        ← Todas as senhas e configurações
├── Makefile                    ← Comandos de conveniência
├── Jenkinsfile                 ← Pipeline declarativo completo
├── docker-compose.yml          ← Apps + Observabilidade
├── docker-compose.ci.yml       ← CI/CD (Jenkins, SonarQube, Nexus, Artifactory)
│
├── app1-python/
│   ├── app.py                  ← Flask app
│   ├── requirements.txt
│   ├── Dockerfile
│   ├── sonar-project.properties
│   └── tests/
│
├── app2-node/
│   ├── index.js                ← Express app
│   ├── package.json
│   ├── Dockerfile
│   ├── sonar-project.properties
│   └── tests/
│
├── nginx/
│   └── nginx.conf              ← Proxy reverso + cache HTTP
│
├── ci/
│   ├── jenkins/
│   │   ├── Dockerfile          ← Jenkins + sonar-scanner + dep-check + docker
│   │   ├── plugins.txt         ← Lista de plugins instalados
│   │   └── casc.yaml           ← Jenkins Configuration as Code (auto-configuração)
│   └── scripts/
│       ├── Dockerfile.init     ← Container de inicialização
│       └── init-services.sh    ← Configura SonarQube, Nexus, Artifactory e gera tokens
│
├── monitoring/
│   ├── prometheus.yml
│   └── grafana/datasources/
│
└── docs/
    └── architecture.md         ← Diagrama + análise + melhorias
```

---

## 🛑 Parar / Limpar

```bash
make down    # Para tudo, mantém volumes
make clean   # Para tudo e apaga volumes (reset total)
```

---

## 💡 Detalhes de Automação

### Por que não precisa configurar nada manualmente?

1. **`init-services`** (container Alpine) roda **antes** do Jenkins:
   - Aguarda SonarQube, Nexus e Artifactory ficarem saudáveis
   - Configura senhas, cria projetos e repositórios
   - Gera o token do SonarQube e salva em volume compartilhado `/secrets/`

2. **Jenkins JCasC** (`casc.yaml`) lê os segredos do volume `/secrets/` com a sintaxe `${readFile:/secrets/sonar-token}` e configura automaticamente:
   - Credenciais (SonarQube, Nexus, Artifactory)
   - Servidor SonarQube
   - Job da pipeline

3. **Pipeline** (`Jenkinsfile`) usa `pollSCM` para detectar mudanças e rodar automaticamente.

---

## 🔧 Personalização

Edite o `.env` para trocar portas ou senhas antes de subir:

```bash
# Exemplo: mudar porta do Jenkins
JENKINS_PORT=9090
```

Para mudar o comportamento da pipeline, edite o `Jenkinsfile` diretamente.

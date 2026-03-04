# ── DevOps Challenge 2025 ──────────────────────────────────────────────────────
# Uso: make <target>
#
#   make up        → só as apps (nginx, redis, obs)
#   make up-ci     → apps + CI/CD completo (Jenkins, SonarQube, Nexus, Artifactory)
#   make all       → alias para up-ci
#   make down      → para tudo
#   make clean     → para e remove volumes
#   make logs      → logs de todos os serviços
#   make status    → status dos containers
#   make pipeline  → acionar pipeline manualmente via API Jenkins
#   make open      → abre todas as UIs no navegador

COMPOSE       = docker compose
COMPOSE_CI    = docker compose -f docker-compose.yml -f docker-compose.ci.yml
JENKINS_URL   = http://localhost:8088
JENKINS_USER  = admin
JENKINS_PASS  = admin123

.PHONY: all up up-ci down clean logs status pipeline open help

all: up-ci

## apps + CI/CD — um único comando
up-ci:
	@echo "🚀 Iniciando stack completa (apps + CI/CD)..."
	@# Criar rede antes caso não exista
	@docker network inspect devops-net >/dev/null 2>&1 || docker network create devops-net
	@$(COMPOSE_CI) up -d --build
	@echo ""
	@echo "════════════════════════════════════════════════════════"
	@echo " ✅  Stack iniciada! Aguardando serviços ficarem prontos..."
	@echo "════════════════════════════════════════════════════════"
	@echo " 🌐 Apps          → http://localhost:8080/app1/"
	@echo " 🔧 Jenkins       → http://localhost:8088  (admin/admin123)"
	@echo " 🔍 SonarQube     → http://localhost:9000  (admin/admin123)"
	@echo " 📦 Nexus         → http://localhost:8081  (admin/admin123)"
	@echo " 🏺 Artifactory   → http://localhost:8082  (admin/password)"
	@echo " 📊 Grafana       → http://localhost:3001  (admin/admin)"
	@echo " 📈 Prometheus    → http://localhost:9090"
	@echo "════════════════════════════════════════════════════════"
	@echo " ⏳ SonarQube e Artifactory levam ~2-3 min para iniciar"
	@echo " ⏳ Jenkins inicia após os serviços estarem prontos"
	@echo "════════════════════════════════════════════════════════"

## só as aplicações + observabilidade
up:
	@docker network inspect devops-net >/dev/null 2>&1 || docker network create devops-net
	$(COMPOSE) up -d --build
	@echo "✅ Apps no ar em http://localhost:8080"

## parar todos os serviços
down:
	$(COMPOSE_CI) down
	$(COMPOSE) down 2>/dev/null || true

## parar e remover volumes (reset completo)
clean:
	$(COMPOSE_CI) down -v --remove-orphans
	$(COMPOSE) down -v --remove-orphans 2>/dev/null || true
	@docker network rm devops-net 2>/dev/null || true
	@echo "✅ Ambiente limpo"

## logs em tempo real
logs:
	$(COMPOSE_CI) logs -f --tail=50

## status dos containers
status:
	@$(COMPOSE_CI) ps

## acionar pipeline Jenkins via API (sem clicar)
pipeline:
	@echo "Acionando pipeline Jenkins..."
	@curl -sf -X POST \
		"$(JENKINS_URL)/job/devops-challenge-pipeline/build" \
		--user "$(JENKINS_USER):$(JENKINS_PASS)" \
		&& echo "✅ Pipeline iniciada!" \
		|| echo "⚠️  Falha ao acionar — Jenkins pode estar iniciando ainda"

## inicializa git no projeto (necessário para Jenkins SCM)
git-init:
	@if [ ! -d ".git" ]; then \
		git init -b main; \
		git add -A; \
		git -c user.email="ci@local" -c user.name="CI" commit -m "initial commit"; \
		echo "✅ Repositório git inicializado"; \
	else \
		echo "✅ Git já inicializado"; \
	fi

## abre todas as UIs no navegador (Linux/macOS)
open:
	@xdg-open http://localhost:8080/app1/ 2>/dev/null || open http://localhost:8080/app1/ 2>/dev/null || true
	@xdg-open http://localhost:8088       2>/dev/null || open http://localhost:8088       2>/dev/null || true
	@xdg-open http://localhost:9000       2>/dev/null || open http://localhost:9000       2>/dev/null || true
	@xdg-open http://localhost:8081       2>/dev/null || open http://localhost:8081       2>/dev/null || true
	@xdg-open http://localhost:8082       2>/dev/null || open http://localhost:8082       2>/dev/null || true
	@xdg-open http://localhost:3001       2>/dev/null || open http://localhost:3001       2>/dev/null || true

## ajuda
help:
	@echo ""
	@echo "DevOps Challenge 2025 — Comandos disponíveis:"
	@echo ""
	@echo "  make all       → Sobe stack completa (apps + CI/CD)"
	@echo "  make up        → Sobe só as aplicações"
	@echo "  make up-ci     → Sobe stack completa"
	@echo "  make down      → Para todos os serviços"
	@echo "  make clean     → Para e apaga volumes"
	@echo "  make logs      → Logs em tempo real"
	@echo "  make status    → Status dos containers"
	@echo "  make pipeline  → Aciona pipeline Jenkins via API"
	@echo "  make git-init  → Inicializa git local"
	@echo "  make open      → Abre UIs no navegador"
	@echo ""

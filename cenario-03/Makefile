# ── DevOps Challenge 2025 ──────────────────────────────────────────────────────
COMPOSE       = docker compose
COMPOSE_CI    = docker compose -f docker-compose.yml -f docker-compose.ci.yml
JENKINS_URL   = http://localhost:8088
JENKINS_USER  = admin
JENKINS_PASS  = admin123

.PHONY: all up up-ci down clean logs status pipeline git-init open trust-cert help

all: up-ci

## apps + CI/CD — um único comando
up-ci:
	@echo "🚀 Iniciando stack completa (apps + CI/CD)..."
	@docker network inspect devops-net >/dev/null 2>&1 || docker network create devops-net
	@$(COMPOSE_CI) up -d --build
	@echo ""
	@echo "══════════════════════════════════════════════════════════"
	@echo " ✅  Stack iniciada!"
	@echo "══════════════════════════════════════════════════════════"
	@echo " 🌐 Apps  HTTP  → http://localhost:8080       (→ HTTPS)"
	@echo " 🔒 Apps  HTTPS → https://localhost:8443/app1/"
	@echo "                  https://localhost:8443/app2/"
	@echo " 🔧 Jenkins      → http://localhost:8088  (admin/admin123)"
	@echo " 🔍 SonarQube    → http://localhost:9000  (admin/admin123)"
	@echo " 📦 Nexus        → http://localhost:8081  (admin/admin123)"
	@echo " 🏺 Artifactory  → http://localhost:8082  (admin/password)"
	@echo " 📊 Grafana      → http://localhost:3001  (admin/admin)"
	@echo " 📈 Prometheus   → http://localhost:9090"
	@echo "══════════════════════════════════════════════════════════"
	@echo " ⏳ SonarQube e Artifactory levam ~2-3 min para iniciar"
	@echo " ⏳ Jenkins inicia após os demais serviços estarem prontos"
	@echo " 🔒 Certificado TLS self-signed — rode: make trust-cert"
	@echo "══════════════════════════════════════════════════════════"

## só apps + observabilidade (sem CI/CD)
up:
	@docker network inspect devops-net >/dev/null 2>&1 || docker network create devops-net
	$(COMPOSE) up -d --build
	@echo "✅ Apps no ar:"
	@echo "  HTTP  → http://localhost:8080  (redireciona para HTTPS)"
	@echo "  HTTPS → https://localhost:8443/app1/"
	@echo "          https://localhost:8443/app2/"

## parar todos os serviços
down:
	$(COMPOSE_CI) down 2>/dev/null || true

## reset total (remove volumes)
clean:
	$(COMPOSE_CI) down -v --remove-orphans 2>/dev/null || true
	$(COMPOSE)    down -v --remove-orphans 2>/dev/null || true
	@docker network rm devops-net 2>/dev/null || true
	@echo "✅ Ambiente limpo"

## logs em tempo real
logs:
	$(COMPOSE_CI) logs -f --tail=50

## status
status:
	@$(COMPOSE_CI) ps

## acionar pipeline via API
pipeline:
	@echo "Acionando pipeline Jenkins..."
	@curl -sf -X POST "${JENKINS_URL}/job/devops-challenge-pipeline/build" \
		--user "${JENKINS_USER}:${JENKINS_PASS}" \
		&& echo "✅ Pipeline iniciada!" \
		|| echo "⚠️  Jenkins pode estar ainda iniciando"

## git init (necessário para Jenkins SCM local)
git-init:
	@if [ ! -d ".git" ]; then \
		git init -b main; \
		git add -A; \
		git -c user.email="ci@local" -c user.name="CI" commit -m "initial commit"; \
		echo "✅ Git inicializado"; \
	else \
		echo "✅ Git já inicializado"; \
	fi

## confiar no certificado self-signed (Linux)
trust-cert:
	@echo "Aguardando cert-gen terminar..."
	@docker run --rm -v devops-challenge-2025_tls_certs:/certs alpine cat /certs/nginx.crt > /tmp/devops-challenge.crt 2>/dev/null || \
	 docker run --rm -v tls_certs:/certs alpine cat /certs/nginx.crt > /tmp/devops-challenge.crt
	@echo ""
	@echo "Certificado exportado em /tmp/devops-challenge.crt"
	@if command -v update-ca-certificates >/dev/null 2>&1; then \
		sudo cp /tmp/devops-challenge.crt /usr/local/share/ca-certificates/devops-challenge.crt; \
		sudo update-ca-certificates; \
		echo "✅ Certificado adicionado ao sistema (Debian/Ubuntu)"; \
	elif command -v certutil >/dev/null 2>&1; then \
		certutil -d sql:$$HOME/.pki/nssdb -A -t "CT,," -n "devops-challenge" -i /tmp/devops-challenge.crt; \
		echo "✅ Certificado adicionado ao NSS (Chrome/Firefox)"; \
	else \
		echo "ℹ️  Importe manualmente /tmp/devops-challenge.crt no seu navegador"; \
	fi

## abre UIs no browser
open:
	@xdg-open https://localhost:8443/app1/ 2>/dev/null || open https://localhost:8443/app1/ 2>/dev/null || true
	@xdg-open http://localhost:8088         2>/dev/null || open http://localhost:8088         2>/dev/null || true
	@xdg-open http://localhost:9000         2>/dev/null || open http://localhost:9000         2>/dev/null || true
	@xdg-open http://localhost:3001         2>/dev/null || open http://localhost:3001         2>/dev/null || true

## ajuda
help:
	@echo ""
	@echo "DevOps Challenge 2025 — Comandos:"
	@echo ""
	@echo "  make all        → Stack completa (apps + CI/CD) — padrão"
	@echo "  make up         → Só as aplicações + observabilidade"
	@echo "  make up-ci      → Stack completa"
	@echo "  make down       → Para tudo"
	@echo "  make clean      → Para e apaga volumes"
	@echo "  make logs       → Logs em tempo real"
	@echo "  make status     → Status containers"
	@echo "  make pipeline   → Aciona pipeline Jenkins via API"
	@echo "  make git-init   → Inicializa git local"
	@echo "  make trust-cert → Confia no certificado TLS self-signed"
	@echo "  make open       → Abre UIs no browser"
	@echo ""

# ══════════════════════════════════════════════════════════════════
# K3s + GitOps targets
# ══════════════════════════════════════════════════════════════════

## instala K3s + ArgoCD + toda a stack K8s (requer root)
k3s-install:
	@echo "🚀 Instalando K3s + GitOps stack..."
	@chmod +x scripts/install-k3s.sh
	@sudo bash scripts/install-k3s.sh

## desinstala K3s completamente
k3s-uninstall:
	@echo "🗑️  Desinstalando K3s..."
	@sudo /usr/local/bin/k3s-uninstall.sh 2>/dev/null || true
	@echo "✅ K3s removido"

## status de todos os pods K8s
k3s-status:
	@echo "════ Apps (devops-challenge) ════"
	@kubectl get pods,svc,hpa -n devops-challenge 2>/dev/null || echo "K3s não disponível"
	@echo ""
	@echo "════ Monitoring ════"
	@kubectl get pods,svc -n monitoring 2>/dev/null || true
	@echo ""
	@echo "════ ArgoCD ════"
	@kubectl get pods -n argocd 2>/dev/null || true
	@echo ""
	@echo "════ Nodes ════"
	@kubectl get nodes -o wide 2>/dev/null || true

## abre ArgoCD UI
k3s-argocd:
	@PASS=$$(kubectl -n argocd get secret argocd-initial-admin-secret \
		-o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "admin")
	@echo "ArgoCD → http://localhost:30080  (admin / $$PASS)"
	@xdg-open http://localhost:30080 2>/dev/null || open http://localhost:30080 2>/dev/null || true

## sync manual de todas as apps ArgoCD
k3s-sync:
	@argocd app sync app1-python app2-node redis-sentinel haproxy monitoring-stack \
		--insecure --server localhost:30080 2>/dev/null || echo "argocd CLI não disponível"

## rollback de uma app — uso: make k3s-rollback APP=app1-python
k3s-rollback:
	@argocd app rollback $(APP) --insecure --server localhost:30080

## mostrar logs de um pod — uso: make k3s-logs APP=app1
k3s-logs:
	@kubectl logs -n devops-challenge -l app=$(APP) --tail=100 -f

## relatório de recursos do cluster
k3s-resources:
	@echo "════ Resource Usage (kubectl top) ════"
	@kubectl top nodes 2>/dev/null || echo "metrics-server não disponível"
	@kubectl top pods -n devops-challenge 2>/dev/null || true

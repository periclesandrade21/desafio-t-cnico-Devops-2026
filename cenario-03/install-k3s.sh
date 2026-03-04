#!/usr/bin/env bash
# =============================================================================
#  DevOps Challenge 2025 — install-k3s.sh
#  Instala K3s + ArgoCD + cert-manager + Traefik + toda a stack de forma
#  totalmente automatizada. Não precisa de nenhuma intervenção manual.
# =============================================================================
set -euo pipefail

# ── Cores ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[K3S]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; exit 1; }
section() { echo -e "\n${BOLD}${CYAN}══ $* ══${NC}\n"; }

# ── Verificar pré-requisitos ───────────────────────────────────────────────────
section "Verificando pré-requisitos"

[ "$(id -u)" -eq 0 ] || error "Execute como root: sudo $0"
command -v curl   >/dev/null 2>&1 || error "curl não encontrado"
command -v git    >/dev/null 2>&1 || error "git não encontrado"

MEM_TOTAL_MB=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
CPU_CORES=$(nproc)
DISK_FREE_GB=$(df -BG / | awk 'NR==2{print int($4)}')

info "RAM disponível: ${MEM_TOTAL_MB} MB"
info "CPUs: ${CPU_CORES}"
info "Disco livre: ${DISK_FREE_GB} GB"

[ "$MEM_TOTAL_MB"  -ge 3072 ] || warn "⚠️  Mínimo recomendado: 4GB RAM (você tem ${MEM_TOTAL_MB}MB)"
[ "$CPU_CORES"     -ge 2    ] || warn "⚠️  Mínimo recomendado: 2 CPUs"
[ "$DISK_FREE_GB"  -ge 20   ] || warn "⚠️  Mínimo recomendado: 20GB disco livre"

# Detectar OS
if   [ -f /etc/debian_version ]; then OS_FAMILY="debian"
elif [ -f /etc/redhat-release ];  then OS_FAMILY="rhel"
else OS_FAMILY="unknown"; fi
info "OS Family: $OS_FAMILY"

# ── Variáveis configuráveis ────────────────────────────────────────────────────
K3S_VERSION="${K3S_VERSION:-v1.30.2+k3s1}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.11.3}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.15.1}"
NAMESPACE_APPS="devops-challenge"
NAMESPACE_MONITORING="monitoring"
NAMESPACE_CICD="cicd"
KUBECONFIG_PATH="/etc/rancher/k3s/k3s.yaml"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

export KUBECONFIG="$KUBECONFIG_PATH"

# ── Funções auxiliares ─────────────────────────────────────────────────────────
retry() {
  local n=0 max=30 delay=10
  until "$@"; do
    n=$((n+1))
    [ $n -ge $max ] && error "Falhou após $max tentativas: $*"
    warn "Tentativa $n/$max — aguardando ${delay}s..."
    sleep $delay
  done
}

kubectl_wait_ready() {
  local ns="$1" resource="$2" label="$3" timeout="${4:-120s}"
  info "Aguardando $resource ($label) em $ns ficar pronto..."
  kubectl wait --for=condition=ready \
    --timeout="$timeout" \
    -n "$ns" "$resource" -l "$label" 2>/dev/null || \
  kubectl rollout status -n "$ns" "$resource" --timeout="$timeout" 2>/dev/null || true
}

# =============================================================================
section "1. Instalando K3s"
# =============================================================================
if command -v k3s >/dev/null 2>&1 && k3s kubectl get nodes >/dev/null 2>&1; then
  success "K3s já está instalado e rodando"
else
  info "Baixando e instalando K3s ${K3S_VERSION}..."

  # Configurar K3s para não instalar o Traefik padrão (vamos usar o nosso)
  # e habilitar métricas do servidor
  mkdir -p /etc/rancher/k3s
  cat > /etc/rancher/k3s/config.yaml << 'K3SCFG'
write-kubeconfig-mode: "0644"
disable:
  - servicelb     # usaremos MetalLB ou NodePort
tls-san:
  - "localhost"
  - "127.0.0.1"
kube-apiserver-arg:
  - "enable-admission-plugins=NodeRestriction"
kubelet-arg:
  - "max-pods=250"
K3SCFG

  curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION="$K3S_VERSION" \
    INSTALL_K3S_EXEC="server --disable=servicelb" \
    sh -

  # Aguardar K3s ficar pronto
  retry bash -c "k3s kubectl get nodes 2>/dev/null | grep -q ' Ready'"
  success "K3s ${K3S_VERSION} instalado"
fi

# Copiar kubeconfig para o usuário que chamou o script (sudo)
REAL_USER="${SUDO_USER:-$USER}"
if [ "$REAL_USER" != "root" ]; then
  REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
  mkdir -p "$REAL_HOME/.kube"
  cp "$KUBECONFIG_PATH" "$REAL_HOME/.kube/config"
  chown "$REAL_USER:$REAL_USER" "$REAL_HOME/.kube/config"
  chmod 600 "$REAL_HOME/.kube/config"
  success "kubeconfig copiado para $REAL_HOME/.kube/config"
fi

# Alias kubectl → k3s kubectl para conveniência
if ! command -v kubectl >/dev/null 2>&1; then
  ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl
  success "kubectl → k3s symlink criado"
fi

# =============================================================================
section "2. Instalando Helm"
# =============================================================================
if ! command -v helm >/dev/null 2>&1; then
  info "Instalando Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  success "Helm instalado: $(helm version --short)"
else
  success "Helm já instalado: $(helm version --short)"
fi

# =============================================================================
section "3. Criando Namespaces"
# =============================================================================
kubectl apply -f "$PROJECT_DIR/k8s/namespaces/namespaces.yaml"
success "Namespaces criados"

# =============================================================================
section "4. Instalando cert-manager (TLS automático)"
# =============================================================================
if ! kubectl get ns cert-manager >/dev/null 2>&1; then
  info "Instalando cert-manager ${CERT_MANAGER_VERSION}..."
  kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
  kubectl_wait_ready "cert-manager" "pod" "app.kubernetes.io/component=webhook" "180s"
  success "cert-manager instalado"
else
  success "cert-manager já instalado"
fi

# Criar ClusterIssuer para self-signed (dev) e ACME (prod)
kubectl apply -f "$PROJECT_DIR/k8s/ingress/cluster-issuer.yaml"
success "ClusterIssuers configurados"

# =============================================================================
section "5. Instalando Traefik (Ingress Controller)"
# =============================================================================
helm repo add traefik https://traefik.github.io/charts 2>/dev/null || true
helm repo update >/dev/null

helm upgrade --install traefik traefik/traefik \
  --namespace kube-system \
  --create-namespace \
  --values "$PROJECT_DIR/k8s/ingress/traefik-values.yaml" \
  --wait --timeout 120s || warn "Traefik pode já estar instalado via K3s built-in"

success "Traefik configurado"

# =============================================================================
section "6. Instalando ArgoCD (GitOps)"
# =============================================================================
if ! kubectl get ns argocd >/dev/null 2>&1; then
  info "Instalando ArgoCD ${ARGOCD_VERSION}..."
  kubectl create namespace argocd
  kubectl apply -n argocd \
    -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
  kubectl_wait_ready "argocd" "deployment" "app.kubernetes.io/name=argocd-server" "300s"
  success "ArgoCD instalado"
else
  success "ArgoCD já instalado"
fi

# Patch ArgoCD para modo insecure (TLS será terminado pelo Traefik)
kubectl patch deployment argocd-server -n argocd \
  --type='merge' \
  -p='{"spec":{"template":{"spec":{"containers":[{"name":"argocd-server","args":["argocd-server","--insecure"]}]}}}}' \
  >/dev/null 2>&1 || true

# Obter senha inicial do ArgoCD
ARGOCD_INITIAL_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "admin")

info "ArgoCD senha inicial: ${ARGOCD_INITIAL_PASS}"
echo "$ARGOCD_INITIAL_PASS" > /tmp/argocd-initial-password.txt

# Instalar CLI do ArgoCD
if ! command -v argocd >/dev/null 2>&1; then
  info "Instalando argocd CLI..."
  curl -sSL -o /usr/local/bin/argocd \
    "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
  chmod +x /usr/local/bin/argocd
  success "argocd CLI instalado"
fi

# Expor ArgoCD via NodePort para acesso local
kubectl patch svc argocd-server -n argocd \
  -p '{"spec":{"type":"NodePort","ports":[{"port":80,"targetPort":8080,"nodePort":30080}]}}' \
  >/dev/null 2>&1 || true

success "ArgoCD disponível em http://localhost:30080 (admin / ${ARGOCD_INITIAL_PASS})"

# =============================================================================
section "7. Configurando secrets da aplicação"
# =============================================================================
kubectl apply -f "$PROJECT_DIR/k8s/apps/secrets.yaml"
success "Secrets da aplicação criados"

# =============================================================================
section "8. Deploy das aplicações via K8s manifests"
# =============================================================================
info "Aplicando manifests..."
kubectl apply -f "$PROJECT_DIR/k8s/namespaces/"
kubectl apply -f "$PROJECT_DIR/k8s/redis/"
kubectl apply -f "$PROJECT_DIR/k8s/apps/app1/"
kubectl apply -f "$PROJECT_DIR/k8s/apps/app2/"
kubectl apply -f "$PROJECT_DIR/k8s/haproxy/"
kubectl apply -f "$PROJECT_DIR/k8s/ingress/"

kubectl_wait_ready "$NAMESPACE_APPS" "deployment" "app=app1" "120s"
kubectl_wait_ready "$NAMESPACE_APPS" "deployment" "app=app2" "120s"
success "Aplicações deployadas"

# =============================================================================
section "9. Deploy do stack de observabilidade"
# =============================================================================
kubectl apply -f "$PROJECT_DIR/k8s/monitoring/alertmanager/"
kubectl apply -f "$PROJECT_DIR/k8s/monitoring/loki/"
kubectl apply -f "$PROJECT_DIR/k8s/monitoring/promtail/"
kubectl apply -f "$PROJECT_DIR/k8s/monitoring/jaeger/"
kubectl apply -f "$PROJECT_DIR/k8s/monitoring/otel/"
success "Stack de observabilidade deployada"

# =============================================================================
section "10. Configurando ArgoCD Applications (GitOps)"
# =============================================================================
# Login no ArgoCD
ARGOCD_SERVER="localhost:30080"
retry argocd login "$ARGOCD_SERVER" \
  --username admin \
  --password "$ARGOCD_INITIAL_PASS" \
  --insecure >/dev/null 2>&1

# Registrar o repositório git local
REPO_PATH="$(cd "$PROJECT_DIR" && pwd)"
argocd repo add "file://${REPO_PATH}" --name "devops-challenge-local" --insecure 2>/dev/null || true

# Aplicar ArgoCD Application manifests
kubectl apply -f "$PROJECT_DIR/k8s/argocd/"
success "ArgoCD Applications configuradas — GitOps ativo"

# =============================================================================
section "11. Resumo Final"
# =============================================================================
echo ""
echo -e "${BOLD}${GREEN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║         K3s + GitOps Stack instalada com sucesso!            ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${CYAN}Serviços disponíveis:${NC}"
echo ""
echo -e "  🌐 App1 (Python)   → https://app1.devops.local  /  http://$(hostname -I | awk '{print $1}'):$(kubectl get svc -n $NAMESPACE_APPS app1 -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo '30001')"
echo -e "  🌐 App2 (Node.js)  → https://app2.devops.local  /  http://$(hostname -I | awk '{print $1}'):$(kubectl get svc -n $NAMESPACE_APPS app2 -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo '30002')"
echo -e "  🔀 HAProxy         → http://$(hostname -I | awk '{print $1}'):30000"
echo -e "  🚀 ArgoCD          → http://localhost:30080     (admin / ${ARGOCD_INITIAL_PASS})"
echo -e "  📊 Grafana         → http://localhost:30300     (admin / admin)"
echo -e "  📈 Prometheus      → http://localhost:30090"
echo -e "  🔍 Jaeger          → http://localhost:30686"
echo -e "  📋 Loki            → http://localhost:30003"
echo ""
echo -e "${YELLOW}Adicione ao /etc/hosts para usar domínios:${NC}"
echo "  $(hostname -I | awk '{print $1}')  app1.devops.local app2.devops.local argocd.devops.local"
echo ""
echo -e "${CYAN}Comandos úteis:${NC}"
echo "  kubectl get pods -n $NAMESPACE_APPS          # Status das apps"
echo "  kubectl get pods -n $NAMESPACE_MONITORING    # Status observabilidade"
echo "  kubectl get pods -n argocd                   # Status ArgoCD"
echo "  argocd app list                              # Apps GitOps"
echo "  make k3s-status                              # Status completo"
echo ""

#!/usr/bin/env bash
set -euo pipefail

# ─── Cores para output ────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INIT]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; exit 1; }

mkdir -p /secrets

# ─── Variáveis com fallback ───────────────────────────────────────────────────
SONAR_ADMIN_PASSWORD=${SONAR_ADMIN_PASSWORD:-admin123}
NEXUS_ADMIN_PASSWORD=${NEXUS_ADMIN_PASSWORD:-admin123}
ARTIFACTORY_ADMIN_PASSWORD=${ARTIFACTORY_ADMIN_PASSWORD:-admin123}
RETRY_MAX=${RETRY_MAX:-30}
RETRY_DELAY=${RETRY_DELAY:-10}

# ─── Helper: retry com backoff ────────────────────────────────────────────────
retry() {
  local n=0
  until "$@"; do
    n=$((n+1))
    [ $n -ge "$RETRY_MAX" ] && error "Comando falhou após $RETRY_MAX tentativas: $*"
    warn "Tentativa $n/$RETRY_MAX falhou, aguardando ${RETRY_DELAY}s..."
    sleep "$RETRY_DELAY"
  done
}

# ─── Helper: verifica se URL retorna código HTTP válido ──────────────────────
_http_ok() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" "$1")
  case "$code" in
    200|401|403) return 0 ;;
    *) warn "HTTP $code de $1" ; return 1 ;;
  esac
}

# ─── Helper: aguarda serviço responder ───────────────────────────────────────
wait_for_service() {
  local name="$1" url="$2"
  info "Aguardando $name ficar disponível em $url ..."
  retry _http_ok "$url"
  success "$name está respondendo"
}

# ─── Helper: verifica credenciais com endpoint que requer auth real ──────────
check_auth() {
  local url="$1" user="$2" pass="$3"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" -u "$user:$pass" "$url")
  [ "$code" = "200" ]
}

# ═══════════════════════════════════════════════════════════════════════════════
# 1. SONARQUBE
# ═══════════════════════════════════════════════════════════════════════════════
info "Configurando SonarQube..."

wait_for_service "SonarQube" "http://sonarqube:9000/api/system/status"

# Aguarda API de autenticação estar pronta
# (status UP não garante que o banco de usuários está inicializado)
info "Aguardando API de autenticação do SonarQube..."
retry _http_ok "http://sonarqube:9000/api/users/search"
success "SonarQube: API de autenticação pronta"

sonar_change_password() {
  local code

  # Tenta alterar de admin:admin para nova senha
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    -u admin:admin \
    -X POST "http://sonarqube:9000/api/users/change_password" \
    -d "login=admin&previousPassword=admin&password=${SONAR_ADMIN_PASSWORD}")
  [ "$code" = "204" ] && return 0

  # 401 = senha padrão não funciona
  # Verifica se a nova senha já está ativa usando endpoint que requer auth real
  if [ "$code" = "401" ]; then
    if check_auth "http://sonarqube:9000/api/projects/search" "admin" "${SONAR_ADMIN_PASSWORD}"; then
      warn "SonarQube: senha já alterada anteriormente, continuando..."
      return 0
    fi
  fi

  warn "SonarQube: change_password retornou HTTP $code"
  return 1
}
retry sonar_change_password
success "SonarQube: senha configurada"

for entry in "devops-app1:DevOps App1 Python" "devops-app2:DevOps App2 Node"; do
  key="${entry%%:*}"; name="${entry##*:}"
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "admin:${SONAR_ADMIN_PASSWORD}" \
    -X POST "http://sonarqube:9000/api/projects/create" \
    -d "project=${key}&name=${name}")
  if [ "$code" = "200" ] || [ "$code" = "201" ] || [ "$code" = "400" ]; then
    success "SonarQube: projeto '${key}' pronto"
  else
    warn "SonarQube: projeto '${key}' retornou HTTP $code"
  fi
done

# Revoga token anterior para evitar acúmulo em reruns
curl -s -u "admin:${SONAR_ADMIN_PASSWORD}" \
  -X POST "http://sonarqube:9000/api/user_tokens/revoke" \
  -d "name=jenkins-ci&login=admin" >/dev/null 2>&1 || true

SONAR_TOKEN=$(curl -sf -u "admin:${SONAR_ADMIN_PASSWORD}" \
  -X POST "http://sonarqube:9000/api/user_tokens/generate" \
  -d "name=jenkins-ci" \
  | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

[ -n "$SONAR_TOKEN" ] || error "Falha ao gerar token SonarQube"
echo -n "$SONAR_TOKEN" > /secrets/sonar-token
success "SonarQube: token gravado em /secrets/sonar-token"

# ═══════════════════════════════════════════════════════════════════════════════
# 2. NEXUS
# ═══════════════════════════════════════════════════════════════════════════════
info "Configurando Nexus..."

wait_for_service "Nexus" "http://nexus:8081/service/rest/v1/status"

NEXUS_PASS_FILE="/nexus-data/admin.password"
if [ -f "$NEXUS_PASS_FILE" ]; then
  NEXUS_INITIAL_PASSWORD=$(cat "$NEXUS_PASS_FILE")
  info "Nexus: usando senha inicial do arquivo $NEXUS_PASS_FILE"
else
  NEXUS_INITIAL_PASSWORD="admin123"
  info "Nexus: usando senha inicial padrão"
fi

nexus_set_password() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "admin:${NEXUS_INITIAL_PASSWORD}" \
    -X PUT "http://nexus:8081/service/rest/v1/security/users/admin/change-password" \
    -H "Content-Type: text/plain" \
    -d "${NEXUS_ADMIN_PASSWORD}")

  [ "$code" = "204" ] && return 0

  if [ "$code" = "401" ]; then
    if check_auth "http://nexus:8081/service/rest/v1/security/users" "admin" "${NEXUS_ADMIN_PASSWORD}"; then
      warn "Nexus: senha já alterada anteriormente, continuando..."
      return 0
    fi
  fi

  warn "Nexus: change-password retornou HTTP $code"
  return 1
}
retry nexus_set_password
success "Nexus: senha configurada"

curl -sf -u "admin:${NEXUS_ADMIN_PASSWORD}" \
  -X PUT "http://nexus:8081/service/rest/v1/security/anonymous" \
  -H "Content-Type: application/json" \
  -d '{"enabled":true,"userId":"anonymous","realmName":"NexusAuthorizingRealm"}' >/dev/null 2>&1 || true

create_nexus_repo() {
  local type="$1" name="$2" body="$3"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "admin:${NEXUS_ADMIN_PASSWORD}" \
    -X POST "http://nexus:8081/service/rest/v1/repositories/${type}" \
    -H "Content-Type: application/json" \
    -d "$body")
  [ "$code" = "201" ] || [ "$code" = "400" ]
}

create_nexus_repo "npm/proxy" "npm-proxy" '{
  "name":"npm-proxy","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "proxy":{"remoteUrl":"https://registry.npmjs.org","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true}
}' && success "Nexus: npm-proxy criado"

create_nexus_repo "pypi/proxy" "pypi-proxy" '{
  "name":"pypi-proxy","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true},
  "proxy":{"remoteUrl":"https://pypi.org","contentMaxAge":1440,"metadataMaxAge":1440},
  "negativeCache":{"enabled":true,"timeToLive":1440},
  "httpClient":{"blocked":false,"autoBlock":true}
}' && success "Nexus: pypi-proxy criado"

create_nexus_repo "docker/hosted" "docker-hosted" '{
  "name":"docker-hosted","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":true,"writePolicy":"ALLOW"},
  "docker":{"v1Enabled":true,"forceBasicAuth":false,"httpPort":5001}
}' && success "Nexus: docker-hosted criado"

create_nexus_repo "raw/hosted" "raw-artifacts" '{
  "name":"raw-artifacts","online":true,
  "storage":{"blobStoreName":"default","strictContentTypeValidation":false,"writePolicy":"ALLOW"}
}' && success "Nexus: raw-artifacts criado"

echo -n "${NEXUS_ADMIN_PASSWORD}" > /secrets/nexus-admin-password

# ═══════════════════════════════════════════════════════════════════════════════
# 3. ARTIFACTORY
# ═══════════════════════════════════════════════════════════════════════════════
info "Configurando Artifactory..."

wait_for_service "Artifactory" "http://artifactory:8082/artifactory/api/system/ping"

artif_update_password() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "admin:password" \
    -X PATCH "http://artifactory:8082/artifactory/api/security/users/admin" \
    -H "Content-Type: application/json" \
    -d "{\"password\":\"${ARTIFACTORY_ADMIN_PASSWORD}\"}")

  [ "$code" = "200" ] && return 0

  if [ "$code" = "400" ] || [ "$code" = "401" ]; then
    if check_auth "http://artifactory:8082/artifactory/api/system/ping" "admin" "${ARTIFACTORY_ADMIN_PASSWORD}"; then
      warn "Artifactory: senha já alterada anteriormente, continuando..."
      return 0
    fi
  fi

  warn "Artifactory: update password retornou HTTP $code"
  return 1
}
retry artif_update_password
success "Artifactory: senha configurada"

create_artif_repo() {
  local key="$1" body="$2"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "admin:${ARTIFACTORY_ADMIN_PASSWORD}" \
    -X PUT "http://artifactory:8082/artifactory/api/repositories/${key}" \
    -H "Content-Type: application/json" \
    -d "$body")
  [ "$code" = "200" ] || [ "$code" = "400" ]
}

create_artif_repo "docker-local" '{
  "rclass":"local","packageType":"docker",
  "repoLayoutRef":"simple-default",
  "description":"Docker images — DevOps Challenge CI/CD"
}' && success "Artifactory: docker-local criado"

create_artif_repo "security-reports" '{
  "rclass":"local","packageType":"generic",
  "description":"SAST e DAST reports — DevOps Challenge"
}' && success "Artifactory: security-reports criado"

echo -n "${ARTIFACTORY_ADMIN_PASSWORD}" > /secrets/artifactory-admin-password

# ═══════════════════════════════════════════════════════════════════════════════
# Resumo
# ═══════════════════════════════════════════════════════════════════════════════
success "Segredos gravados:"
ls -la /secrets/

echo ""
echo "════════════════════════════════════════════════"
echo -e "${GREEN}  Init Services concluído com sucesso!${NC}"
echo "════════════════════════════════════════════════"
echo "  SonarQube   → http://sonarqube:9000"
echo "  Nexus       → http://nexus:8081"
echo "  Artifactory → http://artifactory:8082"
echo "════════════════════════════════════════════════"

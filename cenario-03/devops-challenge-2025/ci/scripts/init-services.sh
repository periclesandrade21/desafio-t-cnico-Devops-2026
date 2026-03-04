#!/usr/bin/env bash
set -euo pipefail

# ─── Cores para output ────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INIT]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; exit 1; }

mkdir -p /secrets

# ─── Helper: retry com backoff ────────────────────────────────────────────────
retry() {
  local n=0 max=30 delay=10
  until "$@"; do
    n=$((n+1))
    [ $n -ge $max ] && error "Comando falhou após $max tentativas: $*"
    warn "Tentativa $n/$max falhou, aguardando ${delay}s..."
    sleep $delay
  done
}

# ═══════════════════════════════════════════════════════════════════════════════
# 1. SONARQUBE
# ═══════════════════════════════════════════════════════════════════════════════
info "Configurando SonarQube..."

sonar_change_password() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    -u admin:admin \
    -X POST "http://sonarqube:9000/api/users/change_password" \
    -d "login=admin&previousPassword=admin&password=${SONAR_ADMIN_PASSWORD}")
  # 204=sucesso, 401=senha já alterada
  [ "$code" = "204" ] || [ "$code" = "401" ]
}
retry sonar_change_password
success "SonarQube: senha configurada"

for entry in "devops-app1:DevOps App1 Python" "devops-app2:DevOps App2 Node"; do
  key="${entry%%:*}"; name="${entry##*:}"
  curl -sf -u "admin:${SONAR_ADMIN_PASSWORD}" \
    -X POST "http://sonarqube:9000/api/projects/create" \
    -d "project=${key}&name=${name}" >/dev/null 2>&1 || true
  success "SonarQube: projeto '${key}' pronto"
done

SONAR_TOKEN=$(curl -sf -u "admin:${SONAR_ADMIN_PASSWORD}" \
  -X POST "http://sonarqube:9000/api/user_tokens/generate" \
  -d "name=jenkins-ci-$(date +%s)" \
  | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

[ -n "$SONAR_TOKEN" ] || error "Falha ao gerar token SonarQube"
echo -n "$SONAR_TOKEN" > /secrets/sonar-token
success "SonarQube: token gravado em /secrets/sonar-token"

# ═══════════════════════════════════════════════════════════════════════════════
# 2. NEXUS
# ═══════════════════════════════════════════════════════════════════════════════
info "Configurando Nexus..."

NEXUS_PASS_FILE="/nexus-data/admin.password"
if [ -f "$NEXUS_PASS_FILE" ]; then
  NEXUS_INITIAL_PASSWORD=$(cat "$NEXUS_PASS_FILE")
else
  NEXUS_INITIAL_PASSWORD="admin123"
fi

nexus_set_password() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "admin:${NEXUS_INITIAL_PASSWORD}" \
    -X PUT "http://nexus:8081/service/rest/v1/security/users/admin/change-password" \
    -H "Content-Type: text/plain" \
    -d "${NEXUS_ADMIN_PASSWORD}")
  [ "$code" = "204" ] || [ "$code" = "401" ]
}
retry nexus_set_password
success "Nexus: senha configurada"

# Ativar Anonymous access (necessário para proxies)
curl -sf -u "admin:${NEXUS_ADMIN_PASSWORD}" \
  -X PUT "http://nexus:8081/service/rest/v1/security/anonymous" \
  -H "Content-Type: application/json" \
  -d '{"enabled":true,"userId":"anonymous","realmName":"NexusAuthorizingRealm"}' >/dev/null 2>&1 || true

# Criar repositórios via REST API v1
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

# Alterar senha padrão 'password' se necessário
artif_update_password() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "admin:password" \
    -X PATCH "http://artifactory:8082/artifactory/api/security/users/admin" \
    -H "Content-Type: application/json" \
    -d "{\"password\":\"${ARTIFACTORY_ADMIN_PASSWORD}\"}")
  # 200=ok, 400=nada mudou, 401=senha já era diferente
  [ "$code" = "200" ] || [ "$code" = "400" ] || [ "$code" = "401" ]
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
echo -e "${GREEN}  Init Services concluído!${NC}"
echo "════════════════════════════════════════════════"
echo "  SonarQube   → http://sonarqube:9000"
echo "  Nexus       → http://nexus:8081"
echo "  Artifactory → http://artifactory:8082"
echo "════════════════════════════════════════════════"

# ── Imagem base Jenkins LTS com JDK 17 ───────────────────────────────────────
FROM jenkins/jenkins:lts-jdk17

# ── Trocar para root para instalar dependências ─────────────────────────────
USER root
RUN groupadd docker \
    && usermod -aG docker jenkins
# ── Dependências básicas do sistema ─────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    wget \
    git \
    unzip \
    jq \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# ── Docker CLI (sem daemon) ─────────────────────────────────────────────────
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
 && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null \
 && apt-get update \
 && apt-get install -y docker-ce-cli \
 && rm -rf /var/lib/apt/lists/*

# ── Node.js 20 + npm ───────────────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
 && apt-get install -y nodejs \
 && rm -rf /var/lib/apt/lists/*

# ── Adicionar jenkins ao grupo docker ───────────────────────────────────────
RUN usermod -aG docker jenkins

# ── SonarScanner CLI ───────────────────────────────────────────────────────
ARG SONAR_SCANNER_VERSION=5.0.1.3006
RUN curl -sL \
    "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux.zip" \
    -o /tmp/sonar-scanner.zip \
    && unzip -q /tmp/sonar-scanner.zip -d /opt \
    && ln -sf "/opt/sonar-scanner-${SONAR_SCANNER_VERSION}-linux/bin/sonar-scanner" \
              /usr/local/bin/sonar-scanner \
    && rm /tmp/sonar-scanner.zip

# ── OWASP Dependency-Check CLI ──────────────────────────────────────────────
ARG DEPCHECK_VERSION=9.2.0
RUN curl -sL \
    "https://github.com/jeremylong/DependencyCheck/releases/download/v${DEPCHECK_VERSION}/dependency-check-${DEPCHECK_VERSION}-release.zip" \
    -o /tmp/depcheck.zip \
    && unzip -q /tmp/depcheck.zip -d /opt \
    && ln -sf /opt/dependency-check/bin/dependency-check.sh \
              /usr/local/bin/dependency-check \
    && rm /tmp/depcheck.zip

# ── Docker Compose v2 ───────────────────────────────────────────────────────
RUN curl -sL "https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64" \
    -o /usr/local/bin/docker-compose \
    && chmod +x /usr/local/bin/docker-compose

# ── Voltar para usuário jenkins ─────────────────────────────────────────────
USER jenkins

# ── Instalar plugins do Jenkins ─────────────────────────────────────────────
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt

ENV JENKINS_UC=https://updates.jenkins.io

RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt


# ── Configuração Jenkins as Code (JCasC) ───────────────────────────────────
COPY casc.yaml /var/jenkins_home/casc.yaml
ENV CASC_JENKINS_CONFIG=/var/jenkins_home/casc.yaml

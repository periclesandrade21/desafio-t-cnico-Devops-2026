FROM node:20-alpine AS builder
WORKDIR /app

# Ferramentas de compilação
RUN apk add --no-cache python3 make g++ git

# Copiar package.json **e package-lock.json**
COPY package*.json ./

# Instalar dependências de produção
RUN npm install --omit=dev  # requer package-lock.json

FROM node:20-alpine
WORKDIR /app

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

COPY --from=builder /app/node_modules ./node_modules
COPY index.js .

EXPOSE 3000
USER appuser
CMD ["node", "index.js"]

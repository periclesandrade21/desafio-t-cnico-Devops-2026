FROM node:20-alpine

RUN apk add --no-cache wget curl

WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev

COPY index.js .

EXPOSE 3000

CMD ["node", "index.js"]

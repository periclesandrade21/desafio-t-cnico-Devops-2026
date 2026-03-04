"use strict";
const express = require("express");
const { createClient } = require("redis");
const client = require("prom-client");

const app = express();
const PORT = process.env.PORT || 3000;
const CACHE_TTL = parseInt(process.env.CACHE_TTL || "60");

// --- Prometheus ---
const register = new client.Registry();
client.collectDefaultMetrics({ register });
const httpCounter = new client.Counter({
  name: "app2_http_requests_total",
  help: "Total HTTP requests",
  labelNames: ["method", "route", "status"],
  registers: [register],
});

// --- Redis ---
let redisClient;
(async () => {
  redisClient = createClient({
    socket: {
      host: process.env.REDIS_HOST || "redis",
      port: parseInt(process.env.REDIS_PORT || "6379"),
    },
    password: process.env.REDIS_PASSWORD || undefined,
  });
  redisClient.on("error", (e) => console.error("Redis:", e.message));
  await redisClient.connect().catch(() => {});
})();

async function getOrSetCache(key, buildFn) {
  try {
    const cached = await redisClient.get(key);
    if (cached) {
      const data = JSON.parse(cached);
      data.cached = true;
      return data;
    }
  } catch (_) {}
  const data = await buildFn();
  data.cached = false;
  try {
    await redisClient.setEx(key, CACHE_TTL, JSON.stringify(data));
  } catch (_) {}
  return data;
}

app.get("/", async (req, res) => {
  httpCounter.inc({ method: "GET", route: "/", status: 200 });
  const data = await getOrSetCache("app2:hello", async () => ({
    message: "Hello from App2 — Node.js/Express!",
    app: "app2",
  }));
  res.json(data);
});

app.get("/time", async (req, res) => {
  httpCounter.inc({ method: "GET", route: "/time", status: 200 });
  const data = await getOrSetCache("app2:time", async () => ({
    server_time: new Date().toISOString(),
    app: "app2",
  }));
  res.json(data);
});

app.get("/health", (req, res) => {
  res.json({ status: "ok", app: "app2" });
});

app.get("/metrics", async (req, res) => {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
});

module.exports = app;

if (require.main === module) {
  app.listen(PORT, () => console.log(`App2 on :${PORT}`));
}

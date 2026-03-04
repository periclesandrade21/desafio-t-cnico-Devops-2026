const express = require("express");
const { createClient } = require("redis");
const client = require("prom-client");

const app = express();
const PORT = process.env.PORT || 3000;
const CACHE_TTL = 60; // seconds

// Prometheus metrics
const register = new client.Registry();
client.collectDefaultMetrics({ register });
const httpRequests = new client.Counter({
  name: "app2_http_requests_total",
  help: "Total HTTP requests",
  labelNames: ["method", "route", "status"],
  registers: [register],
});

// Redis
const redis = createClient({
  socket: {
    host: process.env.REDIS_HOST || "redis",
    port: parseInt(process.env.REDIS_PORT || "6379"),
  },
});
redis.on("error", (err) => console.error("Redis error:", err));
redis.connect();

async function getOrSetCache(key, buildFn) {
  const cached = await redis.get(key);
  if (cached) {
    const data = JSON.parse(cached);
    data.cached = true;
    return data;
  }
  const data = await buildFn();
  data.cached = false;
  await redis.setEx(key, CACHE_TTL, JSON.stringify(data));
  return data;
}

app.get("/", async (req, res) => {
  httpRequests.inc({ method: "GET", route: "/", status: 200 });
  const data = await getOrSetCache("app2:hello", async () => ({
    message: "Hello from App 2 — Node.js/Express!",
    app: "app2",
  }));
  res.json(data);
});

app.get("/time", async (req, res) => {
  httpRequests.inc({ method: "GET", route: "/time", status: 200 });
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

app.listen(PORT, () => console.log(`App2 running on port ${PORT}`));

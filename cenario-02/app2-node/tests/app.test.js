const request = require("supertest");
const app = require("../index");

jest.mock("redis", () => ({
  createClient: () => ({
    connect: jest.fn().mockResolvedValue(undefined),
    get: jest.fn().mockResolvedValue(null),
    setEx: jest.fn().mockResolvedValue("OK"),
    on: jest.fn(),
  }),
}));

describe("App2 — Node.js/Express", () => {
  test("GET / returns 200 with message", async () => {
    const res = await request(app).get("/");
    expect(res.statusCode).toBe(200);
    expect(res.body.message).toMatch(/App2/);
    expect(res.body.app).toBe("app2");
  });

  test("GET /time returns server_time", async () => {
    const res = await request(app).get("/time");
    expect(res.statusCode).toBe(200);
    expect(res.body.server_time).toBeDefined();
    expect(new Date(res.body.server_time).getTime()).not.toBeNaN();
  });

  test("GET /health returns ok", async () => {
    const res = await request(app).get("/health");
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe("ok");
  });

  test("GET /metrics returns prometheus format", async () => {
    const res = await request(app).get("/metrics");
    expect(res.statusCode).toBe(200);
    expect(res.text).toContain("# HELP");
  });
});

from flask import Flask, jsonify
from datetime import datetime
import redis as redis_client_lib
import os
import json

from prometheus_flask_exporter import PrometheusMetrics

app = Flask(__name__)
metrics = PrometheusMetrics(app)
metrics.info("app_info", "App1 Python/Flask", version="1.0.0", app="app1")

redis_client = redis_client_lib.Redis(
    host=os.getenv("REDIS_HOST", "redis"),
    port=int(os.getenv("REDIS_PORT", 6379)),
    decode_responses=True
)

CACHE_TTL = 10  # seconds — App1 cache: 10s

def get_or_set_cache(key, value_fn):
    cached = redis_client.get(key)
    if cached:
        data = json.loads(cached)
        data["cached"] = True
        return data
    data = value_fn()
    data["cached"] = False
    redis_client.setex(key, CACHE_TTL, json.dumps(data))
    return data

@app.route("/")
def hello():
    def build():
        return {"message": "Hello from App 1 — Python/Flask!", "app": "app1"}
    return jsonify(get_or_set_cache("app1:hello", build))

@app.route("/time")
def current_time():
    def build():
        return {"server_time": datetime.now().isoformat(), "app": "app1"}
    return jsonify(get_or_set_cache("app1:time", build))

@app.route("/health")
@metrics.do_not_track()
def health():
    return jsonify({"status": "ok", "app": "app1"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

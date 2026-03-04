from flask import Flask, jsonify
from datetime import datetime
from prometheus_flask_exporter import PrometheusMetrics
import redis
import os
import json

app = Flask(__name__)
metrics = PrometheusMetrics(app)
metrics.info("app_info", "App1 Python Flask", version="1.0.0")

redis_client = redis.Redis(
    host=os.getenv("REDIS_HOST", "redis"),
    port=int(os.getenv("REDIS_PORT", 6379)),
    password=os.getenv("REDIS_PASSWORD", ""),
    decode_responses=True,
)

CACHE_TTL = int(os.getenv("CACHE_TTL", 10))


def get_or_set_cache(key, value_fn):
    try:
        cached = redis_client.get(key)
        if cached:
            data = json.loads(cached)
            data["cached"] = True
            return data
    except Exception:
        pass
    data = value_fn()
    data["cached"] = False
    try:
        redis_client.setex(key, CACHE_TTL, json.dumps(data))
    except Exception:
        pass
    return data


@app.route("/")
def hello():
    return jsonify(
        get_or_set_cache(
            "app1:hello",
            lambda: {"message": "Hello from App1 — Python/Flask!", "app": "app1"},
        )
    )


@app.route("/time")
def current_time():
    return jsonify(
        get_or_set_cache(
            "app1:time",
            lambda: {"server_time": datetime.now().isoformat(), "app": "app1"},
        )
    )


@app.route("/health")
@metrics.do_not_track()
def health():
    return jsonify({"status": "ok", "app": "app1"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)

from flask import Flask, jsonify
import os
import logging

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

app = Flask(__name__)


app.config["SECRET_KEY"] = os.environ["SECRET_KEY"]

@app.route("/")
def index():
    return jsonify({"service": "orders-api", "status": "ok"})

@app.route("/healthz")
def health():
    return jsonify({"status": "healthy"}), 200

@app.route("/orders")
def orders():
    return jsonify({"orders": [{"id": 1, "item": "widget", "qty": 3}]})

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=False)
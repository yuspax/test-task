from flask import Flask, Response, jsonify

app = Flask(__name__)


@app.get("/")
def hello() -> Response:
    return Response("Hello, World!\n", mimetype="text/plain")


@app.get("/healthz")
def healthz() -> Response:
    return jsonify(status="ok")

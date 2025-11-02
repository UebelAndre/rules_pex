"""Pex example source."""

import os

from flask import Flask

app = Flask(__name__)


@app.route("/")
def hello_world():
    return "hello world!"


if __name__ == "__main__":
    app.run(port=int(os.environ.get("FLASK_RUN_PORT", 5000)))

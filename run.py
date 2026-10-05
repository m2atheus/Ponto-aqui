"""Entrada de desenvolvimento; a configuração permanece na Application Factory."""

import os

from app import create_app


if __name__ == "__main__":
    app = create_app()
    app.run(debug=os.getenv("FLASK_DEBUG", "0") == "1")

"""Entrada de desenvolvimento; a configuração permanece na Application Factory."""

import os

from app import create_app


if __name__ == "__main__":
    app = create_app()
    app.run(
        host="0.0.0.0",
        port=5000,
        debug=os.getenv("FLASK_DEBUG", "0") == "1",
        # Atualiza rotas e serviços sem precisar habilitar o debugger.
        use_reloader=os.getenv("FLASK_RELOAD", "1") == "1",
    )

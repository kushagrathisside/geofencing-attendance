#!/bin/bash

echo "[SETUP] Creating environment with uv..."

cd flask_api

uv venv
source .venv/bin/activate

uv pip install -r requirements.txt

echo "[OK] Backend ready."

cd ../flutter_app
flutter pub get

echo "[OK] Flutter ready."

echo ""
echo "Run:"
echo "  bash start.sh"

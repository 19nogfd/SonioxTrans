#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
PYTHON="${PYTHON:-$ROOT/.venv/bin/python}"
PYINSTALLER="${PYINSTALLER:-$ROOT/.venv/bin/pyinstaller}"

if [[ ! -x "$PYTHON" || ! -x "$PYINSTALLER" ]]; then
  echo "找不到构建环境。请先运行：python3 -m venv .venv && .venv/bin/pip install -r requirements-build.txt"
  exit 1
fi

cd "$ROOT"
rm -rf build dist
"$PYTHON" -m py_compile server.py
"$PYINSTALLER" --noconfirm --clean server.spec
"$ROOT/dist/server/server" --self-test
echo "后端构建完成：$ROOT/dist/server"

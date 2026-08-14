#!/usr/bin/env bash
# Rebuild the AgentCore deployment package on ~/Desktop/deployment_package.zip
set -euo pipefail

cd "$(dirname "$0")"

PYTHON_VERSION="3.12"
OUT_ZIP="${OUT_ZIP:-$HOME/Desktop/deployment_package.zip}"

rm -rf deployment_package
uv pip install \
  --python-platform aarch64-manylinux2014 \
  --python-version "$PYTHON_VERSION" \
  --target=deployment_package \
  --only-binary=:all: \
  -r pyproject.toml

find deployment_package -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

# AgentCore needs 644 on files and 755 on directories and executables.
find deployment_package -type d -exec chmod 755 {} +
find deployment_package -type f -exec chmod 644 {} +
find deployment_package -type f \( -name "*.so" -o -path "*/bin/*" \) -exec chmod 755 {} +
chmod 644 main.py

# Any x86 wheel here would deploy fine and then fail at runtime.
if find deployment_package -name "*.so" -exec file {} \; | grep -v aarch64 | grep -q .; then
  echo "ERROR: found non-aarch64 native libraries" >&2
  exit 1
fi

rm -f "$OUT_ZIP"
(cd deployment_package && zip -qr "$OUT_ZIP" .)
zip -qj "$OUT_ZIP" main.py

echo "Built $OUT_ZIP"
ls -lh "$OUT_ZIP"

#!/usr/bin/env bash
# Exec the actual vendor terminal jar so systemd owns the listener process.
set -euo pipefail

REF_ROOT="${THETADATA_REF_ROOT:-/opt/stevetrading/shared/Data-Preprocessor}"
JAVA_BIN="${THETADATA_JAVA_BIN:-/bin/java}"
LOG_DIR="${THETADATA_LOG_DIRECTORY:-$REF_ROOT/pipeline_data/paper_trading_logs}"
CREDENTIALS="${THETADATA_CREDS_FILE:-$REF_ROOT/creds.txt}"

JAR="$(find "$REF_ROOT/lib" -maxdepth 1 -type f -name '[0-9]*.jar' -printf '%f\n' 2>/dev/null | sort -V | tail -n 1)"
if [[ -z "$JAR" ]]; then
  echo "ThetaData terminal jar not found under $REF_ROOT/lib" >&2
  exit 2
fi

exec "$JAVA_BIN" -Xms1G -Xmx3G -XX:+IgnoreUnrecognizedVMOptions \
  --sun-misc-unsafe-memory-access=allow --enable-native-access=ALL-UNNAMED \
  -jar "$REF_ROOT/lib/$JAR" --creds-file="$CREDENTIALS" --log-directory="$LOG_DIR"

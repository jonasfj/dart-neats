#!/bin/bash
set -e

TOOL_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
ROOT_DIR="$TOOL_DIR/.."

# Create temp folder to be deleted when script exits
TEMP_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEMP_DIR"' EXIT

GIT_REPOSITORY='https://github.com/json-schema-org/JSON-Schema-Test-Suite.git'

git clone "$GIT_REPOSITORY" "$TEMP_DIR"
GIT_REVISION=$(cd "$TEMP_DIR" && git rev-parse HEAD)

TARGET_DIR="$ROOT_DIR/third_party/json-schema-test-suite/"
OLD_TARGET_DIR="$ROOT_DIR/third_party/json-schema-test-suite_old/"
mv "$TARGET_DIR" "$OLD_TARGET_DIR"
mkdir -p "$TARGET_DIR"
cp "$OLD_TARGET_DIR/README.google.md" "$TARGET_DIR/README.google.md"
rm -rf "$OLD_TARGET_DIR"

cp "$TEMP_DIR/LICENSE" "$TARGET_DIR/LICENSE"
cp "$TEMP_DIR/README.md" "$TARGET_DIR/README.md"
mkdir -p "$TARGET_DIR/tests"
cp -r "$TEMP_DIR/tests/draft2020-12" "$TARGET_DIR/tests/"
cp -r "$TEMP_DIR/remotes" "$TARGET_DIR/"

cat << EOF > "$TARGET_DIR/METADATA"
name: "JSON Schema Test Suite"
description:
    "Test suite for JSON schema"

third_party {
  url {
    type: GIT
    value: "https://github.com/json-schema-org/JSON-Schema-Test-Suite"
  }
  version: "$GIT_REVISION"
  last_upgrade_date { $(date  '+year: %Y month: %m day: %d') }
  license_type: NOTICE
}
EOF

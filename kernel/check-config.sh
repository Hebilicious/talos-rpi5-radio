#!/usr/bin/env bash
# Fails if an option of the fragment is missing from the kernel config after
# `make olddefconfig`.
#
# usage: check-config.sh <fragment> <config>
set -euo pipefail

fragment=$1
config=$2
missing=0

while IFS= read -r line; do
  [[ -z $line || $line == \#* ]] && continue

  if ! grep -qxF -- "$line" "$config"; then
    echo "missing from $config: $line (found: $(grep -E "^(# )?${line%%=*}[= ]" "$config" || echo nothing))"
    missing=1
  fi
done < "$fragment"

if [[ $missing -ne 0 ]]; then
  exit 1
fi

echo "all options of $fragment are in $config"

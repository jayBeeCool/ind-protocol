#!/usr/bin/env bash
set -euo pipefail
forge fmt
forge test -q
forge lint contracts

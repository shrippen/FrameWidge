#!/usr/bin/env bash
# Runs the full test suite: unit tests, then both smoke tests.
# See tests/README.md for what each layer actually covers.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILED=0

echo "############################################"
echo "# Unit tests (tests/run_unit_tests.sh)"
echo "############################################"
"$SCRIPT_DIR/run_unit_tests.sh" || FAILED=1

echo
echo "############################################"
echo "# Smoke test: package/static checks"
echo "############################################"
"$SCRIPT_DIR/smoke/smoke_package.sh" || FAILED=1

echo
echo "############################################"
echo "# Smoke test: real Plasma host (plasmawindowed)"
echo "############################################"
"$SCRIPT_DIR/smoke/smoke_plasmawindowed.sh" || FAILED=1

echo
if [[ $FAILED -eq 0 ]]; then
    echo "ALL GREEN"
else
    echo "SOME CHECKS FAILED - see above"
fi
exit $FAILED

#!/usr/bin/env bash
# Prints the version number this build gets. The VERSION file holds the NEXT
# official version (for example 1.0); what kind of build this is comes from
# the environment variable SUFUN_VERSION_KIND:
#
#   release   official release            1.0        (tag v1.0)
#   rc<N>     pre-release ("시험판") N     1.0rc<N>   (tag v1.0rc<N>)
#   dev       everything else             1.0dev     (test builds from main; default)
#
# pacman compares versions like this:  1.0dev < 1.0rc1 < 1.0rc2 < ... < 1.0
# so an installed test or pre-release system accepts every later pre-release and
# the official release as an update, and never goes backwards.
# (No "~" or "-" in the number: pacman would sort "1.0~rc1" AFTER "1.0".)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base="$(tr -d '[:space:]' < "$HERE/VERSION")"
kind="${SUFUN_VERSION_KIND:-dev}"
[[ $base =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "VERSION must look like 1.0 (found '$base')" >&2; exit 1; }
case "$kind" in
  release) echo "$base" ;;
  dev)     echo "${base}dev" ;;
  *)       [[ $kind =~ ^rc[1-9][0-9]*$ ]] || { echo "SUFUN_VERSION_KIND must be release, dev or rc<N> (found '$kind')" >&2; exit 1; }
           echo "${base}${kind}" ;;
esac

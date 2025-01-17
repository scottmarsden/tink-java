#!/bin/bash
# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
################################################################################

# This script checks if the Maven direct dependencies of the given Bazel target
# match the ones in the POM file. In case of discrepancies, it prints the diff
# on standard output and exits with exit code 1.

set -eo pipefail

usage() {
  echo "Usage: $0 [-h] [-e <excluded group ids>] <bazel target> <pom file>"
  echo
  echo " <bazel target>: The Bazel target that generate the JAR."
  echo " <pom file>: The POM file path."
  echo " -e: Comma-separated list of excluded group ids (optional)."
  echo " -h: Show this help message."
  exit 1
}

BAZEL_CMD="bazel"
# Prefer using Bazelisk if available.
if command -v "bazelisk" &> /dev/null; then
  BAZEL_CMD="bazelisk"
fi
readonly BAZEL_CMD

BAZEL_TARGET=
POM_FILE=
EXCLUDED_GROUP_IDS=""

process_params() {
  while getopts "he:" opt; do
    case "${opt}" in
      e) EXCLUDED_GROUP_IDS="${OPTARG}" ;;
      *) usage ;;
    esac
  done
  shift $((OPTIND - 1))
  readonly EXCLUDED_GROUP_IDS

  BAZEL_TARGET="$1"
  POM_FILE="$2"

  readonly BAZEL_TARGET
  readonly POM_FILE
}

process_params "$@"

readonly MAVEN_DIRECT_DEPS="$(mktemp)"
mvn dependency:list -DoutputFile="${MAVEN_DIRECT_DEPS}" \
  -DexcludeGroupIds="${EXCLUDED_GROUP_IDS}" -DexcludeTransitive=true -f \
  "${POM_FILE}" -q

# Get the sorted list of deps and get them in the form:
#    <groupId>:<artifactId>:<version>
readonly POM_FILE_DEPS="$(cat "${MAVEN_DIRECT_DEPS}" \
  | grep compile | cut -d: -f1,2,4 | sed -E 's/^\s+//' | sort)"

readonly BAZEL_MAVEN_DEPS="$("${BAZEL_CMD}" query --output=build \
  'attr(tags, .*,filter(@maven, deps('"${BAZEL_TARGET}"', 2)))' \
    | grep maven_coordinates | cut -d'"' -f2 | cut -d'=' -f2 | sort)"

if ! cmp -s <(echo "${BAZEL_MAVEN_DEPS}" ) <(echo "${POM_FILE_DEPS}"); then
  echo "ERROR: There are the following mismatches between the dependencies in \
${BAZEL_TARGET} and the ones in ${POM_FILE}:" >&2
  echo
  diff -y <(echo "${BAZEL_MAVEN_DEPS}" ) <(echo "${POM_FILE_DEPS}")
  echo
  exit 1
fi

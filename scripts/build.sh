#! /usr/bin/env bash

BUILD_DIR_NAME="build"
if [ "$1" ] ; then
  BUILD_DIR_NAME="$1"
fi
PROJECT_DIR="$(dirname "$0")/.."
BUILD_PATH="$PROJECT_DIR/$BUILD_DIR_NAME"
mkdir -p "$BUILD_PATH" &&
cmake -S "$PROJECT_DIR" -B "$BUILD_PATH" -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=gcc-14 -DCMAKE_CXX_COMPILER=g++-14 &&
cmake --build "$BUILD_PATH" -t cxlbench -j

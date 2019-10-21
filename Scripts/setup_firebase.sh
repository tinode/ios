#!/bin/bash

# This script selects appropriate GoogleService-Info.plist for the given build configuration.

# Names of source resource files
GOOG_DEV=${PROJECT_DIR}/${TARGET_NAME}/GoogleService-Info-Development.plist
GOOG_PROD=${PROJECT_DIR}/${TARGET_NAME}/GoogleService-Info-Production.plist

# Destination location for the resource. Also rename it to GoogleService-Info.plist
GOOG_DST=${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/GoogleService-Info.plist

# Select appropriate GoogleService-Info-ABC123.plist for the current build.
if [ "${CONFIGURATION}" == "Release" ]; then
  GOOG_SRC="${GOOG_PROD}"
else
  GOOG_SRC="${GOOG_DEV}"
fi

if [ ! -f "$GOOG_SRC" ]; then
  echo "Missing 'GoogleService-Info.plist' source at '${GOOG_SRC}"
  exit 1
fi

cp "${GOOG_SRC}" "${GOOG_DST}"

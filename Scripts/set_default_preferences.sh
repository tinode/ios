#!/bin/bash

# This script assigns DefaultValue for host name and TLS in Settings.bundle/Root.plist preferences
# reading them from build configuration Info.plist.

# Location of Settings.bundle/Root.plist to update
prefs_file="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Settings.bundle/Root.plist"
# Location of Info.plist to read values from
info_plist="$TARGET_BUILD_DIR/$INFOPLIST_PATH"

# Find array entry with the necessary key
# Iterate at most 10 array entries until either the key is found or all entries iterated.
# @param: key to find
find_array_entry() {
  for i in {1..10}
  do
    local key=$(/usr/libexec/PlistBuddy -c "Print PreferenceSpecifiers:${i}:Key" "$prefs_file" 2>/dev/null)
    if [ -z "$key" ]; then
      return 0
    fi
    if [[ $key == "$1" ]]; then
      return $i
    fi
  done
  return 0
}

# Find key for the host name
find_array_entry "host_name_preference"
hn_index=$?
if [ "$hn_index" -eq 0 ]; then
  echo "Entry host_name_preference not found"
  exit -1
fi
# Find key for TLS use
find_array_entry "use_tls_preference"
tls_index=$?
if [ "$tls_index" -eq 0 ]; then
  echo "Entry use_tls_preference not found"
  exit -1
fi

# Read values from Info.plist
host_name=$(/usr/libexec/PlistBuddy -c "Print :HOST_NAME" "$info_plist" 2>/dev/null)
use_tls=$(/usr/libexec/PlistBuddy -c "Print :USE_TLS" "$info_plist" 2>/dev/null)
if [ -z "$host_name" ] || [ -z "$use_tls" ]; then
  echo "Missing host name '$host_name' or TLS value '$use_tls'"
  exit -1
fi

# Assign values as appropriate
/usr/libexec/PlistBuddy -c "Set PreferenceSpecifiers:${hn_index}:DefaultValue $host_name" "$prefs_file"
/usr/libexec/PlistBuddy -c "Set PreferenceSpecifiers:${tls_index}:DefaultValue $use_tls" "$prefs_file"

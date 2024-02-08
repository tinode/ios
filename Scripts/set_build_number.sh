#!/bin/bash

# Automatically sets version of target based on most recent tag in git
# Automatically sets build number to number of commits
#
# Add script to build phase in xcode at the top of the chain named "set build number"
# put this script in the root of the xcode project in a directory called scripts (good idea to version control this too)
# call the script as $SRCROOT/scripts/set_build_number.sh in xcode

cd "$SRCROOT"

git=$(sh /etc/profile; which git)
number_of_commits=$("$git" rev-list HEAD --count)
tag=$("$git" describe --tags --always --abbrev=0)
git_version=${tag#?}

sed -i -e "/GIT_TAG =/ s/= .*/= $git_version/" prod.xcconfig
sed -i -e "/GIT_COMMIT_COUNT =/ s/= .*/= $number_of_commits/" prod.xcconfig

# Delete old version of the file.
rm prod.xcconfig-e

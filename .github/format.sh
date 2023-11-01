#!/usr/bin/env bash

# Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md).
# Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# This script runs clang-format and fixes copyright headers on all relevant files in the repo.
# This is the primary script responsible for fixing style violations.

# Derived from:
# https://github.com/godotengine/godot/blob/4.0/misc/scripts/format.sh

set -uo pipefail

if [ $# -eq 0 ]; then
    # Loop through all code files tracked by Git.
    files=$(git ls-files -- '*.gd' \
                ':!:humanoid/*' ':!:deresuteme/*' ':!:.git/*' ':!:thirdparty/*' ':!:addons/vrm' ':!:addons/godot_state_charts' ':!:addons/xr_vignette' \
                ':!:addons/unidot_importer' ':!:addons/Godot-MToon-Shader' ':!:addons/gut' ':!:addons/smoothing' \
                ':!:.git/*' ':!:thirdparty/*' ':!:*/thirdparty/*' ':!:platform/android/java/lib/src/com/google/*' \
                ':!:*-so_wrap.*' ':!:tests/python_build/*')
else
    # $1 should be a file listing file paths to process. Used in CI.
    files=$(cat "$1" | grep -v "thirdparty/" | grep -E "\.(c|h|cpp|hpp|cc|hh|cxx|m|mm|inc|java|glsl)$" | grep -v "platform/android/java/lib/src/com/google/" | grep -v "\-so_wrap\." | grep -v "tests/python_build/")
fi

# Fix copyright headers, but not all files get them.
for f in $files; do
    if [[ "$f" == *"inc" ]]; then
        continue
    elif [[ "$f" == *"glsl" ]]; then
        continue
    elif [[ "$f" == "platform/android/java/lib/src/org/godotengine/godot/gl/GLSurfaceView"* ]]; then
        continue
    elif [[ "$f" == "platform/android/java/lib/src/org/godotengine/godot/gl/EGLLogWrapper"* ]]; then
        continue
    elif [[ "$f" == "platform/android/java/lib/src/org/godotengine/godot/utils/ProcessPhoenix"* ]]; then
        continue
    fi

    python .github/copyright_headers.py "$f"
done

diff=$(git diff --color)

# If no diff has been generated all is OK, clean up, and exit.
if [ -z "$diff" ] ; then
    printf "\e[1;32m*** Files in this commit comply with the clang-format style rules.\e[0m\n"
    exit 0
fi

# A diff has been created, notify the user, clean up, and exit.
printf "\n\e[1;33m*** The following changes must be made to comply with the formatting rules:\e[0m\n\n"
# Perl commands replace trailing spaces with `·` and tabs with `<TAB>`.
printf "$diff\n" | perl -pe 's/(.*[^ ])( +)(\e\[m)$/my $spaces="·" x length($2); sprintf("$1$spaces$3")/ge' | perl -pe 's/(.*[^\t])(\t+)(\e\[m)$/my $tabs="<TAB>" x length($2); sprintf("$1$tabs$3")/ge'

printf "\n\e[1;91m*** Please fix your commit(s) with 'git commit --amend' or 'git rebase -i <hash>'\e[0m\n"
exit 1

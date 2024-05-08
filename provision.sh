#!/bin/bash

set -euo pipefail

SOURCE_ROOT="yyjson"
TARGET_ROOT="yyjson-build"
tools=("cmake" "gcc")

install_apt_packages_of_executables() {
	local packages=()
	for command in "$@"; do
		if ! command -v "$command" >/dev/null 2>&1; then
			packages+=("$command")
		fi
	done
	if [[ ${#packages[@]} -gt 0 ]]; then
		package_list="${packages[@]}"
		echo "Installing missing APT packages: $package_list ..."
		sudo apt install "${packages[@]}"
	fi
}

mkdir -p "${TARGET_ROOT}"
pushd "${TARGET_ROOT}" > /dev/null

install_apt_packages_of_executables "${tools[@]}"

# ok to use "-march=native" because of no distribution
cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="-march=native" ../"${SOURCE_ROOT}"
make --quiet

popd > /dev/null

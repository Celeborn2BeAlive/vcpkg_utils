# Vcpkg Utilities

This repository contains utilities for using Vcpkg (https://github.com/Microsoft/vcpkg).

Vcpkg is a multi-plateform C++ library manager. It is designed to download and build open source libraries. For a given instance of vcpkg, a CMake toolchain file is provided to help finding libraries from a CMake based project.

## Vcpkg3rdParty.cmake

This is a CMake module to be used in a CMake script to download vcpkg and build libraries. An important feature of this script is the possibility of specifying the version of each library to install. Indeed, to build a specific version of a library with vcpkg it is necessary to checkout files at a specific revision. Vcpkg3rdParty.cmake allows to automatically do this checkout by using a version string instead of the commit sha.

Here is an example of a CMake script using this module:

```cmake
include(cmake/Vcpkg3rdParty.cmake)

# Initialize the module (download and bootstrap vcpkg if necessary, pull last revisions)
vcpkg_init()

# Specify which packages to build and install, with a version provided
vcpkg_require(
    PACKAGE glfw3
    VERSION 3.2.1-3
)
vcpkg_require(
    PACKAGE imgui
    VERSION 1.69
)

# If no version is provided, the latest is used
vcpkg_require(
    PACKAGE nlohmann-json
)

# Ask vcpk to build and install packages
vcpkg_install()
```

Then we call CMake in script mode with correct parameters:

```shell
cmake -DVCPKG_3RDPARTY_ROOT="/where/to/clone/vcpkg" -DVCPKG_3RDPARTY_TRIPLET=x64-windows -P "script.cmake"
```

For a more complete example, see this repository https://github.com/Celeborn2BeAlive/c2ba-graphics-cpp-sdk (build-scripts folder).

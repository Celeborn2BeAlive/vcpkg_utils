# Vcpkg3rdParty.cmake - v1.0 - CMake script to handle third parties in a cmake project with vcpkg - public domain
# Laurent NOEL, 2019

cmake_minimum_required(VERSION 3.14)

set(ENV{VCPKG_ROOT} "") # Unset VCPKG_ROOT env var, otherwise the vcpkg executable would use that location instead of our local folder

if (NOT VCPKG_3RDPARTY_ROOT)
    message(FATAL_ERROR "VCPKG_3RDPARTY_ROOT must be set to the path where vcpkg should be cloned.")
endif()

if (NOT VCPKG_3RDPARTY_TRIPLET)
    message(FATAL_ERROR "VCPKG_3RDPARTY_TRIPLET must be set to the triplet to use to build packages with vcpkg.")
endif()

# Path to git repository can be specified by the caller, otherwise use default path
if (NOT VCPKG_3RDPARTY_GIT_REPOSITORY)
    set(VCPKG_3RDPARTY_GIT_REPOSITORY "https://github.com/Microsoft/vcpkg.git")
endif()

# Clone vcpkg if necessary, then discard all uncommited changes and pull
function (vcpkg_update_repository)
    if (NOT EXISTS ${VCPKG_3RDPARTY_ROOT})
        message("git clone ${VCPKG_3RDPARTY_GIT_REPOSITORY} ${VCPKG_3RDPARTY_ROOT}")
        execute_process(
            COMMAND git clone ${VCPKG_3RDPARTY_GIT_REPOSITORY} ${VCPKG_3RDPARTY_ROOT}
            RESULT_VARIABLE ret)
            if (NOT ret EQUAL "0")
                message(FATAL_ERROR "Unable to run 'git clone' to download vcpkg, check if git is in your PATH.")
            endif()
    endif()
    execute_process(
        COMMAND git reset HEAD *
        WORKING_DIRECTORY ${VCPKG_3RDPARTY_ROOT}
    )
    execute_process(
        COMMAND git reset --hard
        WORKING_DIRECTORY ${VCPKG_3RDPARTY_ROOT}
    )
    execute_process(
        COMMAND git pull
        WORKING_DIRECTORY ${VCPKG_3RDPARTY_ROOT}
    )
endfunction()

# Try to find vcpkg executable in variable VCPKG_EXECUTABLE. If it does not exist then run bootstrap script.
macro (vcpkg_find_executable)
    find_program(VCPKG_EXECUTABLE
        vcpkg PATHS "${VCPKG_3RDPARTY_ROOT}")
    if (NOT VCPKG_EXECUTABLE)
        if (CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
            execute_process(
                COMMAND "bootstrap-vcpkg.bat"
                WORKING_DIRECTORY "${VCPKG_3RDPARTY_ROOT}"
                RESULT_VARIABLE ret
            )
        else ()
            execute_process(
                COMMAND  "bootstrap-vcpkg.sh"
                WORKING_DIRECTORY "${VCPKG_3RDPARTY_ROOT}"
                RESULT_VARIABLE ret
            )
        endif ()
        if (NOT ret EQUAL "0")
            message(FATAL_ERROR "Unable to bootstrap vcpkg.")
        endif()
        find_program(VCPKG_EXECUTABLE
            vcpkg PATHS "${VCPKG_3RDPARTY_ROOT}")
    endif ()
endmacro()

# Must be called before calling vcpkg_require() and vcpkg_install()
macro (vcpkg_init)
    vcpkg_update_repository()
    vcpkg_find_executable()
endmacro()

# Specify a package to be installed at a specific version 
macro (vcpkg_require)
    cmake_parse_arguments(_arg "" "PACKAGE;VERSION" "" ${ARGN})

    if (NOT _arg_PACKAGE)
        message(FATAL_ERROR "vcpkg_require() should be called with a PACKAGE argument.")
    endif()

    # Check if the package is already installed, and get the commit sha if it is
    if (EXISTS "${VCPKG_3RDPARTY_ROOT}/VCPKG_3RDPARTY_COMMIT_SHA_${_arg_PACKAGE}")
        file(READ "${VCPKG_3RDPARTY_ROOT}/VCPKG_3RDPARTY_COMMIT_SHA_${_arg_PACKAGE}" INSTALLED_COMMIT_SHA)
    endif()
    
    if (_arg_VERSION)
        execute_process(
            COMMAND git rev-list master -- ports/${_arg_PACKAGE}
            WORKING_DIRECTORY ${VCPKG_3RDPARTY_ROOT}
            OUTPUT_VARIABLE GIT_REV_LIST_OUTPUT
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        string(REPLACE "\n" ";" GIT_REV_LIST_OUTPUT ${GIT_REV_LIST_OUTPUT})
        foreach(COMMIT_SHA ${GIT_REV_LIST_OUTPUT})
            execute_process(
                COMMAND git show ${COMMIT_SHA}:ports/${_arg_PACKAGE}/CONTROL
                WORKING_DIRECTORY ${VCPKG_3RDPARTY_ROOT}
                OUTPUT_VARIABLE GIT_SHOW_OUTPUT
            )
            string(REGEX MATCH "Version: ([^\n]*)" _ ${GIT_SHOW_OUTPUT})
            set(VERSION ${CMAKE_MATCH_1})
            list(APPEND FOUND_VERSIONS ${VERSION})
            if (${VERSION} STREQUAL ${_arg_VERSION})
                set(FOUND_COMMIT_SHA ${COMMIT_SHA})
                set(FOUND_VERSION ${VERSION})
                break()
            endif()
        endforeach()

        if(NOT FOUND_COMMIT_SHA)
            message(STATUS "vcpkg_install(): version ${_arg_VERSION} not found in revision history of package ${_arg_PACKAGE}.")
            message(STATUS "Found versions are:")
            list(REMOVE_DUPLICATES FOUND_VERSIONS)
            foreach(VERS ${FOUND_VERSIONS})
                message(STATUS ${VERS})
            endforeach()
            message(FATAL_ERROR "Unable to install ${_arg_PACKAGE} at required version. CMake will exit.")
        endif()

        execute_process(
            COMMAND git checkout ${FOUND_COMMIT_SHA} -- ports/${_arg_PACKAGE}
            WORKING_DIRECTORY ${VCPKG_3RDPARTY_ROOT}
        )
    else()
        file(READ "${VCPKG_3RDPARTY_ROOT}/ports/${_arg_PACKAGE}/CONTROL" CONTROL_FILE)
        string(REGEX MATCH "Version: ([^\n]*)" _ ${CONTROL_FILE})
        set(FOUND_VERSION ${CMAKE_MATCH_1})
        execute_process(
            COMMAND git rev-list master -- ports/${_arg_PACKAGE}
            WORKING_DIRECTORY ${VCPKG_3RDPARTY_ROOT}
            OUTPUT_VARIABLE GIT_REV_LIST_OUTPUT
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        string(REPLACE "\n" ";" GIT_REV_LIST_OUTPUT ${GIT_REV_LIST_OUTPUT})
        list(GET ${GIT_REV_LIST_OUTPUT} 0 FOUND_COMMIT_SHA)
        message(${FOUND_COMMIT_SHA})
    endif ()

    if (INSTALLED_COMMIT_SHA)
        if (NOT (${INSTALLED_COMMIT_SHA} STREQUAL ${FOUND_COMMIT_SHA}))
            message(STATUS "Removing previously installed version of package ${_arg_PACKAGE} commit ${INSTALLED_COMMIT_SHA}")
            execute_process (COMMAND ${VCPKG_EXECUTABLE} remove ${_arg_PACKAGE})
        endif()
    endif()

    message(STATUS "vcpkg_require() called to install: ${_arg_PACKAGE} version ${FOUND_VERSION} commit ${FOUND_COMMIT_SHA}")

    file(WRITE "${VCPKG_3RDPARTY_ROOT}/VCPKG_3RDPARTY_COMMIT_SHA_${_arg_PACKAGE}" ${FOUND_COMMIT_SHA})

    list(APPEND VCPKG_PKG_LIST "${_arg_PACKAGE}")
    
endmacro ()

function (vcpkg_install)
    # Remove installed packages that are no longer required
    file(GLOB INSTALLED_COMMIT_SHA_FILE_LIST ${VCPKG_3RDPARTY_ROOT}/VCPKG_3RDPARTY_COMMIT_SHA_*)
    if (INSTALLED_COMMIT_SHA_FILE_LIST)
        foreach (file ${INSTALLED_COMMIT_SHA_FILE_LIST})
            string(REGEX MATCH "VCPKG_3RDPARTY_COMMIT_SHA_(.*)" _ ${file})
            set(PKG_NAME ${CMAKE_MATCH_1})
            if (NOT ${PKG_NAME} IN_LIST VCPKG_PKG_LIST)
                execute_process (COMMAND ${VCPKG_EXECUTABLE} remove ${PKG_NAME})
            endif()
        endforeach()
    endif()

    foreach (pkg ${VCPKG_PKG_LIST})
        list(APPEND VCPKG_INSTALL_LIST "${pkg}:${VCPKG_3RDPARTY_TRIPLET}")
    endforeach()

    execute_process (
        COMMAND ${VCPKG_EXECUTABLE} install ${VCPKG_INSTALL_LIST}
    )
endfunction ()
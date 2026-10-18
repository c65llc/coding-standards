# ProjectWarnings.cmake — lang-14 §2.
#
# Copy to cmake/ProjectWarnings.cmake, rename the PROJECT_ option prefix to
# your project's (the same names CMakePresets.json sets), `include(ProjectWarnings)`
# from the root CMakeLists.txt after project(), and link every target you own
# against `${PROJECT_NAME}_warnings`:
#
#     project(mesh_core LANGUAGES CXX)
#     include(ProjectWarnings)                        # creates mesh_core_warnings
#     target_link_libraries(mesh_core PRIVATE mesh_core_warnings)   # or mesh_core::warnings
#
# The target carries the project's name so two libraries built from this
# template can be combined with FetchContent or add_subdirectory: CMake
# requires library target names to be globally unique, and a fixed name
# (`project_warnings`) would fail the second project's configure.
#
# Warnings are declared once here. Warnings-as-errors is OFF by default so a
# consumer on an untested compiler is never broken by a diagnostic in your
# code; the `ci` preset turns it on (CMAKE_COMPILE_WARNING_AS_ERROR=ON and
# PROJECT_WARNINGS_AS_ERRORS=ON). Vendored targets (third_party/) do NOT link
# the warnings target and carry COMPILE_WARNING_AS_ERROR OFF (lang-14 §16).

if(NOT PROJECT_NAME)
    message(FATAL_ERROR "ProjectWarnings.cmake: include() it after project() — the warnings target is named after the project")
endif()

set(_pw_target "${PROJECT_NAME}_warnings")
if(TARGET ${_pw_target})
    message(FATAL_ERROR "ProjectWarnings.cmake: target '${_pw_target}' already exists — included twice, or two projects share the name '${PROJECT_NAME}'")
endif()

option(PROJECT_WARNINGS_AS_ERRORS "Treat compiler warnings as errors (CI turns this on)" OFF)
option(PROJECT_HARDENED_STDLIB "Enable libstdc++/libc++ assertions in Debug and sanitizer builds" OFF)
option(PROJECT_HARDENING_FLAGS "Enable release hardening flags (FORTIFY, stack protector, RELRO, CFG)" OFF)
option(PROJECT_ENABLE_COVERAGE "Instrument the project's targets for coverage (gcov / llvm-cov; CI turns this on)" OFF)
option(PROJECT_ENABLE_CLANG_TIDY "Run clang-tidy on every translation unit the project owns (CI turns this on)" OFF)

add_library(${_pw_target} INTERFACE)
add_library(${PROJECT_NAME}::warnings ALIAS ${_pw_target})

# --- Language standard (lang-14 §1) ------------------------------------------------
# Declared as a usage requirement of this target, not as CMAKE_CXX_STANDARD in
# a preset: a cache variable would also force C++20 on every dependency the
# project pulls in with FetchContent or add_subdirectory.
target_compile_features(${_pw_target} INTERFACE cxx_std_20)

# --- Clang (incl. Apple Clang) and GCC share a baseline ------------------------
set(PROJECT_WARNINGS_GNU_CLANG
    -Wall
    -Wextra
    -Wpedantic
    -Wshadow
    -Wconversion
    -Wsign-conversion
    -Wnon-virtual-dtor
    -Wold-style-cast
    -Wcast-align
    -Woverloaded-virtual
    -Wnull-dereference
    -Wdouble-promotion
    -Wformat=2
    -Wimplicit-fallthrough
    -Wunused
)

set(PROJECT_WARNINGS_GCC_EXTRA
    -Wmisleading-indentation
    -Wduplicated-cond
    -Wduplicated-branches
    -Wlogical-op
    -Wuseless-cast
)

set(PROJECT_WARNINGS_CLANG_EXTRA
    -Wmost
    -Wextra-semi
    -Wunreachable-code
    # -Wthread-safety only has an effect with the annotations from lang-14 §11;
    # it is harmless without them.
    -Wthread-safety
)

# --- MSVC ------------------------------------------------------------------------
set(PROJECT_WARNINGS_MSVC
    /W4
    /permissive-
    /Zc:__cplusplus
    /Zc:preprocessor
    /utf-8
    /EHsc
    /w14242 # conversion: possible loss of data
    /w14254 # operator: conversion from 'type1:field_bits' to 'type2:field_bits'
    /w14263 # member function does not override any base class virtual member function
    /w14265 # class has virtual functions, but destructor is not virtual
    /w14287 # unsigned/negative constant mismatch
    /we4289 # loop control variable used outside the for-loop scope
    /w14296 # expression is always true/false
    /w14311 # pointer truncation
    /w14545 # expression before comma evaluates to a function which is missing an argument list
    /w14546 # function call before comma missing argument list
    /w14547 # operator before comma has no effect
    /w14549 # operator before comma has no effect; did you intend another operator?
    /w14555 # expression has no effect; expected expression with side-effect
    /w14619 # pragma warning: there is no warning number 'number'
    /w14640 # thread un-safe static member initialization
    /w14826 # conversion is sign-extended
    /w14905 # wide string literal cast to 'LPSTR'
    /w14906 # string literal cast to 'LPWSTR'
    /w14928 # illegal copy-initialization
)

if(MSVC)
    target_compile_options(${_pw_target} INTERFACE ${PROJECT_WARNINGS_MSVC})
    if(PROJECT_WARNINGS_AS_ERRORS)
        target_compile_options(${_pw_target} INTERFACE /WX)
    endif()
elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    target_compile_options(${_pw_target} INTERFACE ${PROJECT_WARNINGS_GNU_CLANG} ${PROJECT_WARNINGS_CLANG_EXTRA})
    if(PROJECT_WARNINGS_AS_ERRORS)
        target_compile_options(${_pw_target} INTERFACE -Werror)
    endif()
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    target_compile_options(${_pw_target} INTERFACE ${PROJECT_WARNINGS_GNU_CLANG} ${PROJECT_WARNINGS_GCC_EXTRA})
    if(PROJECT_WARNINGS_AS_ERRORS)
        target_compile_options(${_pw_target} INTERFACE -Werror)
    endif()
else()
    message(WARNING "${_pw_target}: no warning set for compiler '${CMAKE_CXX_COMPILER_ID}' — add one to cmake/ProjectWarnings.cmake")
endif()

# --- Hardened standard library (lang-14 §13) ------------------------------------
if(PROJECT_HARDENED_STDLIB AND NOT MSVC)
    target_compile_definitions(${_pw_target} INTERFACE
        $<$<CONFIG:Debug>:_GLIBCXX_ASSERTIONS>
        $<$<CONFIG:Debug>:_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_EXTENSIVE>
    )
endif()

# --- Release hardening (lang-14 §17) ------------------------------------------------
if(PROJECT_HARDENING_FLAGS)
    if(MSVC)
        target_compile_options(${_pw_target} INTERFACE /GS /guard:cf /sdl)
        target_link_options(${_pw_target} INTERFACE /DYNAMICBASE /NXCOMPAT /HIGHENTROPYVA /guard:cf)
    else()
        target_compile_definitions(${_pw_target} INTERFACE $<$<NOT:$<CONFIG:Debug>>:_FORTIFY_SOURCE=3>)
        target_compile_options(${_pw_target} INTERFACE -fstack-protector-strong -fstack-clash-protection)
        if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
            target_link_options(${_pw_target} INTERFACE -Wl,-z,relro,-z,now -Wl,-z,noexecstack)
            if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64")
                target_compile_options(${_pw_target} INTERFACE -fcf-protection=full)
            endif()
        endif()
    endif()
endif()

# --- Coverage (lang-14 §12) ----------------------------------------------------------
# Instruments only the targets that link this one, so third-party code never
# counts toward (or against) the 95% gate. Read with `llvm-cov` (Clang) or
# `gcovr` (GCC); MSVC coverage comes from the VS tooling, not compiler flags.
if(PROJECT_ENABLE_COVERAGE)
    if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
        target_compile_options(${_pw_target} INTERFACE -fprofile-instr-generate -fcoverage-mapping)
        target_link_options(${_pw_target} INTERFACE -fprofile-instr-generate)
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
        target_compile_options(${_pw_target} INTERFACE --coverage)
        target_link_options(${_pw_target} INTERFACE --coverage)
    else()
        message(WARNING "${_pw_target}: PROJECT_ENABLE_COVERAGE has no flags for compiler '${CMAKE_CXX_COMPILER_ID}'")
    endif()
endif()

# --- clang-tidy (lang-14 §4) -----------------------------------------------------------
# CMAKE_CXX_CLANG_TIDY initialises the CXX_CLANG_TIDY property of every target
# created after this point in this directory and below, which is why the
# vendored tree (lang-14 §16) sets `set(CMAKE_CXX_CLANG_TIDY "")` before its
# own add_subdirectory() calls. The committed .clang-tidy supplies the checks;
# `--warnings-as-errors=*` makes every finding fail the CI build. Only the
# Makefile and Ninja generators honour it.
if(PROJECT_ENABLE_CLANG_TIDY)
    find_program(PROJECT_CLANG_TIDY_EXE NAMES clang-tidy clang-tidy-18 clang-tidy-17 clang-tidy-16)
    if(NOT PROJECT_CLANG_TIDY_EXE)
        message(FATAL_ERROR "${_pw_target}: PROJECT_ENABLE_CLANG_TIDY is ON but clang-tidy was not found")
    endif()
    if(CMAKE_GENERATOR MATCHES "Visual Studio|Xcode")
        message(FATAL_ERROR "${_pw_target}: CMAKE_CXX_CLANG_TIDY needs the Ninja or Makefile generator (got '${CMAKE_GENERATOR}')")
    endif()
    set(CMAKE_CXX_CLANG_TIDY "${PROJECT_CLANG_TIDY_EXE};--warnings-as-errors=*")
endif()

unset(_pw_target)

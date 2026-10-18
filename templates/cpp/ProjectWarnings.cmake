# ProjectWarnings.cmake — lang-14 §2.
#
# Copy to cmake/ProjectWarnings.cmake, rename the PROJECT_ prefix to your
# project's, `include(ProjectWarnings)` from the root CMakeLists.txt, and link
# every target you own against `project_warnings`:
#
#     add_library(project_warnings INTERFACE)   # created below
#     target_link_libraries(mesh_core PRIVATE project_warnings)
#
# Warnings are declared once here. Warnings-as-errors is OFF by default so a
# consumer on an untested compiler is never broken by a diagnostic in your
# code; the `ci` preset turns it on (CMAKE_COMPILE_WARNING_AS_ERROR=ON and
# PROJECT_WARNINGS_AS_ERRORS=ON). Vendored targets (third_party/) do NOT link
# project_warnings and carry COMPILE_WARNING_AS_ERROR OFF (lang-14 §16).

option(PROJECT_WARNINGS_AS_ERRORS "Treat compiler warnings as errors (CI turns this on)" OFF)
option(PROJECT_HARDENED_STDLIB "Enable libstdc++/libc++ assertions in Debug and sanitizer builds" OFF)
option(PROJECT_HARDENING_FLAGS "Enable release hardening flags (FORTIFY, stack protector, RELRO, CFG)" OFF)

add_library(project_warnings INTERFACE)
add_library(project::warnings ALIAS project_warnings)

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
    target_compile_options(project_warnings INTERFACE ${PROJECT_WARNINGS_MSVC})
    if(PROJECT_WARNINGS_AS_ERRORS)
        target_compile_options(project_warnings INTERFACE /WX)
    endif()
elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    target_compile_options(project_warnings INTERFACE ${PROJECT_WARNINGS_GNU_CLANG} ${PROJECT_WARNINGS_CLANG_EXTRA})
    if(PROJECT_WARNINGS_AS_ERRORS)
        target_compile_options(project_warnings INTERFACE -Werror)
    endif()
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    target_compile_options(project_warnings INTERFACE ${PROJECT_WARNINGS_GNU_CLANG} ${PROJECT_WARNINGS_GCC_EXTRA})
    if(PROJECT_WARNINGS_AS_ERRORS)
        target_compile_options(project_warnings INTERFACE -Werror)
    endif()
else()
    message(WARNING "project_warnings: no warning set for compiler '${CMAKE_CXX_COMPILER_ID}' — add one to cmake/ProjectWarnings.cmake")
endif()

# --- Hardened standard library (lang-14 §13) ------------------------------------
if(PROJECT_HARDENED_STDLIB AND NOT MSVC)
    target_compile_definitions(project_warnings INTERFACE
        $<$<CONFIG:Debug>:_GLIBCXX_ASSERTIONS>
        $<$<CONFIG:Debug>:_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_EXTENSIVE>
    )
endif()

# --- Release hardening (lang-14 §17) ------------------------------------------------
if(PROJECT_HARDENING_FLAGS)
    if(MSVC)
        target_compile_options(project_warnings INTERFACE /GS /guard:cf /sdl)
        target_link_options(project_warnings INTERFACE /DYNAMICBASE /NXCOMPAT /HIGHENTROPYVA /guard:cf)
    else()
        target_compile_definitions(project_warnings INTERFACE $<$<NOT:$<CONFIG:Debug>>:_FORTIFY_SOURCE=3>)
        target_compile_options(project_warnings INTERFACE -fstack-protector-strong -fstack-clash-protection)
        if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
            target_link_options(project_warnings INTERFACE -Wl,-z,relro,-z,now -Wl,-z,noexecstack)
            if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64")
                target_compile_options(project_warnings INTERFACE -fcf-protection=full)
            endif()
        endif()
    endif()
endif()

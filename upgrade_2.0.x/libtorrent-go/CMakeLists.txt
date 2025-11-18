cmake_minimum_required(VERSION 3.14)
project(libtorrent-go-2.0)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Build type
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# Compiler flags
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fPIC -Wall")
set(CMAKE_CXX_FLAGS_RELEASE "-O2 -DNDEBUG")
set(CMAKE_CXX_FLAGS_DEBUG "-g -O0")

# Find required packages
find_package(Boost 1.67 REQUIRED COMPONENTS system)
find_package(SWIG REQUIRED)
find_package(Threads REQUIRED)
find_package(OpenSSL REQUIRED)

include(UseSWIG)

# libtorrent
find_library(LIBTORRENT_LIBRARY torrent-rasterbar
    HINTS /usr/local/lib /usr/lib
)
find_path(LIBTORRENT_INCLUDE_DIR libtorrent/session.hpp
    HINTS /usr/local/include /usr/include
)

if(NOT LIBTORRENT_LIBRARY)
    message(FATAL_ERROR "libtorrent-rasterbar library not found")
endif()

if(NOT LIBTORRENT_INCLUDE_DIR)
    message(FATAL_ERROR "libtorrent headers not found")
endif()

message(STATUS "Found libtorrent: ${LIBTORRENT_LIBRARY}")
message(STATUS "Found libtorrent headers: ${LIBTORRENT_INCLUDE_DIR}")

# Include directories
include_directories(
    ${LIBTORRENT_INCLUDE_DIR}
    ${Boost_INCLUDE_DIRS}
    ${OPENSSL_INCLUDE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}
)

# SWIG settings
set_property(SOURCE libtorrent.i PROPERTY CPLUSPLUS ON)
set_property(SOURCE libtorrent.i PROPERTY SWIG_MODULE_NAME libtorrent)
set_property(SOURCE libtorrent.i PROPERTY COMPILE_OPTIONS -go -cgo -intgosize 64)

# SWIG flags
set(CMAKE_SWIG_FLAGS -go -cgo -intgosize 64)

# Generate SWIG library
swig_add_library(libtorrent
    TYPE SHARED
    LANGUAGE go
    SOURCES libtorrent.i
)

# Link libraries
target_link_libraries(libtorrent
    ${LIBTORRENT_LIBRARY}
    ${Boost_LIBRARIES}
    ${OPENSSL_LIBRARIES}
    Threads::Threads
)

# Set include directories for SWIG target
target_include_directories(libtorrent PRIVATE
    ${LIBTORRENT_INCLUDE_DIR}
    ${Boost_INCLUDE_DIRS}
    ${OPENSSL_INCLUDE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}
)

# libtorrent 2.0.x definitions
target_compile_definitions(libtorrent PRIVATE
    TORRENT_USE_OPENSSL=1
    TORRENT_ABI_VERSION=3
    BOOST_ASIO_SEPARATE_COMPILATION
    BOOST_ASIO_ENABLE_CANCELIO
)

# Installation
install(TARGETS libtorrent
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

# Custom target for Go build
add_custom_target(go-build
    COMMAND ${CMAKE_COMMAND} -E env CGO_ENABLED=1 go build -v ./...
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/go
    DEPENDS libtorrent
    COMMENT "Building Go bindings"
)

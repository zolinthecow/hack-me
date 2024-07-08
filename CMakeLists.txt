cmake_minimum_required(VERSION 3.10)

project(HackMe)

# Specify the C++ standard
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED True)

# Add the executable
add_executable(HackMe main.cpp server/server.cpp)

# Include the directory containing the header files
target_include_directories(HackMe PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/server)
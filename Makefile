CPP_FLAGS=-std=c++17 -Wshadow -Wall -D_GLIBCXX_DEBUG

all: server

server: server.cpp
		g++-13 $(CPP_FLAGS) -g server.cpp -o build/server

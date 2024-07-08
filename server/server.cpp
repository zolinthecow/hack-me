#include <server.h>

#include <iostream>
#include <string>
#include <cstring>
#include <sstream>

#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <sys/wait.h>
#include <signal.h>
#include <unistd.h>

namespace {
    void sigchld_handler(int s)
    {
        // waitpid() might overwrite errno, so we save and restore it:
        int saved_errno = errno;

        while(waitpid(-1, NULL, WNOHANG) > 0);

        errno = saved_errno;
    }

    // get sockaddr, IPv4 or IPv6:
    void *get_in_addr(struct sockaddr *sa)
    {
        if (sa->sa_family == AF_INET) {
            return &(((struct sockaddr_in*)sa)->sin_addr);
        }

        return &(((struct sockaddr_in6*)sa)->sin6_addr);
    }
}

namespace http {
    Server::Server(std::string port): _port(port) {
        _start_server();
    }

    Server::~Server() {
        _close_server();
    }

    void Server::start_listen() {
        if (listen(_sockfd, 10) == -1) {
            std::cerr << "Failed to listen to socket " << _sockfd << std::endl;
            exit(1);
        }

        std::cout << "Waiting for connections.." << std::endl;

        while (1) {
            struct sockaddr_storage incoming_addr;
            socklen_t s_in_size = sizeof incoming_addr;

            _new_fd = accept(_sockfd, (struct sockaddr *)&incoming_addr, &s_in_size);
            if (_new_fd == 01) {
                std::cerr << "Failed to accept" << std::endl;
                continue;
            }

            char incoming_addr_str[INET6_ADDRSTRLEN];
            inet_ntop(incoming_addr.ss_family,
                get_in_addr((struct sockaddr *)&incoming_addr),
                incoming_addr_str, sizeof incoming_addr_str);

            std::cout << "Got connection from " << incoming_addr_str << std::endl;

            if (!fork()) { // this is the child process
                close(_sockfd); // child doesn't need the listener
                const int BUF_SIZE = 30720;
                char buffer[BUF_SIZE] = {0};
                if (read(_new_fd, buffer, BUF_SIZE) == -1) {
                    std::cerr << "FAILED TO READ INCOMING MESSAGE" << std::endl;
                    close(_new_fd);
                    exit(0);
                }
                std::cout << buffer << std::endl;

                std::string htmlFile = "<!DOCTYPE html><html lang=\"en\"><body><h1> HOME </h1><p> Hello from your Server :) </p></body></html>";
                std::string resp = _build_response(htmlFile);

                if (write(_new_fd, resp.c_str(), resp.size()) == -1)
                    perror("send");
                close(_new_fd);
                exit(0);
            }
            close(_new_fd);  // parent doesn't need this
        }
    }

    int Server::_start_server() {
                std::cout << "Binding to socket.." << std::endl;

        struct addrinfo hints;
        std::memset(&hints, 0, sizeof hints);
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_STREAM;
        hints.ai_flags = AI_PASSIVE;

        // Get linked list of valid address descriptions for the port I want
        // to connect to
        struct addrinfo *serv_info;
        int status = getaddrinfo(NULL, _port.c_str(), &hints, &serv_info);
        if (status != 0) {
            std::cerr << "getaddrinfo failed: " << 
                gai_strerror(status) << std::endl;
        }

        // Walk through the list and find the first address I can bind to
        struct addrinfo *p;
        for (p = serv_info; p != NULL; p = p->ai_next) {
            int sockfd = socket(p->ai_family, p->ai_socktype, p->ai_protocol);
            if (sockfd == -1) {
                std::cerr << "Failed to connect: " << 
                    p->ai_family << " " << p->ai_socktype << " " << p->ai_protocol <<
                    std::endl;
                continue;
            }

            // Port could be in use from an old socket, so we tell it to just reuse
            int yes = 1;
            if (setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(int)) == -1) {
                std::cerr << "Failed setsockopt!" << std::endl;
                exit(1);
            }

            // Now we can finally try to bind to the valid socket
            if (bind(sockfd, p->ai_addr, p->ai_addrlen) == -1) {
                close(sockfd);
                std::cerr << "Failed to bind: " << 
                    sockfd << " " << p->ai_addr << std::endl;
                continue;
            }

            // If we got here then we successfully binded to p
            _sockfd = sockfd;
            break;
        }

        freeaddrinfo(serv_info);

        if (p == NULL) {
            std::cerr << "Could not bind to any addresses" << std::endl;
            exit(1);
        }

        // Reap zombie processes
        struct sigaction sa;
        sa.sa_handler = sigchld_handler;
        sigemptyset(&sa.sa_mask);
        sa.sa_flags = SA_RESTART;
        if (sigaction(SIGCHLD, &sa, NULL) == -1) {
            std::cerr << "Failed to set sigaction" << std::endl;
            exit(1);
        }

        std::cout << "Successfully bound to socket " << _sockfd << std::endl;
        return 0;
    }

    void Server::_close_server() {
        close(_sockfd);
        close(_new_fd);
        exit(0);
    }

    std::string Server::_build_response(std::string response_to_send) {
        std::ostringstream ss;
        ss << "HTTP/1.1 200 OK\nContent-Type: text/html\nContent-Length: " <<
            response_to_send.size() << "\n\n" << response_to_send;

        return ss.str();
    }
}
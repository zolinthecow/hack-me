#ifndef SERVER_H
#define SERVER_H

#include <string>

namespace http {
    class Server {
    public:
        Server(std::string port);
        ~Server();

        void start_listen();
    private:
        std::string _port;
        int _sockfd;
        int _new_fd;

        int _start_server();
        void _close_server();
        std::string _build_response(std::string response_to_send);
    };
}

#endif
#include <string>
#include <iostream>
#include <cstring>

#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <netinet/in.h>


int main(int argc, char *argv[]) {
    if (argc != 2) {
        std::cerr << "usage: server hostname\n" << std::endl;
        return 1;
    }

    struct addrinfo hints, *res;
    std::memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;

    int status = getaddrinfo(argv[1], NULL, &hints, &res);
    if (status != 0) {
        std::cerr << "getaddrinfo: " << gai_strerror(status) << std::endl;
        return 2;
    }

    printf("IP addresses for %s:\n\n", argv[1]);

    for (struct addrinfo *p = res; p != NULL; p = p->ai_next) {
        // This should only be ipv4 addresses?
        struct sockaddr_in *ipv4 = (struct sockaddr_in *)p->ai_addr;
        
        void *addr = &(ipv4->sin_addr);
        std::string ipver = "IPv4";
        char ipstr[INET_ADDRSTRLEN];

        inet_ntop(p->ai_family, addr, ipstr, sizeof ipstr);
        std::cout << "  " << ipver << ": " << ipstr << std::endl;
    }

    freeaddrinfo(res);

    return 0;
}
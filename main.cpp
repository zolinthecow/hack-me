#include "server/server.h"

int main() {
    http::Server server = http::Server("8000");
    server.start_listen();

    return 0;
}
#include "TCPInfoProbe.h"

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static void close_if_open(int descriptor)
{
    if (descriptor >= 0) {
        (void)close(descriptor);
    }
}

int tcp_info_access_probe_run(void)
{
    int listener = -1;
    int client = -1;
    int peer = -1;
    int result = 1;
    struct sockaddr_in address;
    socklen_t address_length = sizeof(address);

    listener = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (listener < 0) {
        printf("[tcp-info] listener socket error=%d\n", errno);
        goto out;
    }

    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(listener, (const struct sockaddr *)&address, sizeof(address)) != 0 ||
        listen(listener, 1) != 0 ||
        getsockname(listener, (struct sockaddr *)&address, &address_length) != 0) {
        printf("[tcp-info] listener setup error=%d\n", errno);
        goto out;
    }

    client = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (client < 0 ||
        connect(client, (const struct sockaddr *)&address, sizeof(address)) != 0) {
        printf("[tcp-info] client setup error=%d\n", errno);
        goto out;
    }

    peer = accept(listener, NULL, NULL);
    if (peer < 0) {
        printf("[tcp-info] accept error=%d\n", errno);
        goto out;
    }

    struct tcp_connection_info client_info;
    struct tcp_connection_info peer_info;
    socklen_t client_length = sizeof(client_info);
    socklen_t peer_length = sizeof(peer_info);
    memset(&client_info, 0, sizeof(client_info));
    memset(&peer_info, 0, sizeof(peer_info));

    errno = 0;
    int client_status = getsockopt(
        client, IPPROTO_TCP, TCP_CONNECTION_INFO,
        &client_info, &client_length);
    int client_error = errno;
    errno = 0;
    int peer_status = getsockopt(
        peer, IPPROTO_TCP, TCP_CONNECTION_INFO,
        &peer_info, &peer_length);
    int peer_error = errno;

    printf("[tcp-info] client status=%d error=%d length=%u state=%u "
           "peer status=%d error=%d length=%u state=%u\n",
           client_status, client_error, (unsigned)client_length,
           (unsigned)client_info.tcpi_state,
           peer_status, peer_error, (unsigned)peer_length,
           (unsigned)peer_info.tcpi_state);
    result = (client_status == 0 && peer_status == 0) ? 0 : 2;

out:
    close_if_open(peer);
    close_if_open(client);
    close_if_open(listener);
    return result;
}

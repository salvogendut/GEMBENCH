#ifndef NET_H
#define NET_H

/*
 * TCP socket API — socket 0 only.
 * All functions return 0 on success, -1 on error unless noted otherwise.
 */

#define NET_RX_DATA     1
#define NET_RX_IDLE     2
#define NET_RX_CLOSED   3
#define NET_RX_TIMEOUT  4
#define NET_RX_ERROR    5

/* Open socket 0 in TCP mode, ready to connect. */
int net_socket_open(void);

/* Open socket 0 in TCP server listen mode on the given port.
 * Returns 0 if the socket is now listening, -1 on error.
 * Poll net_is_connected() to detect an incoming client. */
int net_listen(unsigned int port);

/* Connect to ip[4] (big-endian) on the given port (host byte order). */
int net_connect(const unsigned char *ip, unsigned int port);

/* Send len bytes from buf.  Returns 0 on success, -1 on error. */
int net_send(const unsigned char *buf, unsigned int len);

/*
 * Receive up to maxlen bytes into buf.
 * Returns number of bytes actually received (may be 0 if nothing ready).
 */
unsigned int net_recv(unsigned char *buf, unsigned int maxlen);

/* NET_RX_* result associated with the most recent net_recv(). */
unsigned char net_recv_status(void);

/* Graceful close: DISCON then CLOSE. */
void net_close(void);

/* Returns 1 if TCP connection is established, 0 otherwise. */
unsigned char net_is_connected(void);

/* Returns number of bytes waiting in the RX buffer (non-blocking check). */
unsigned int net_rx_available(void);

/* Debug: issue one raw C_NETRECV and report firmware response fields.
 * Only available on M4 build; out_status=resp[3], out_len=resp[4:5]. */
unsigned char net_recv_raw(unsigned char *out_status, unsigned int *out_len);

#endif /* NET_H */

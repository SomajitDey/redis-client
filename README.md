# Redis Client (Bash)

This project consists of 

1. `redis.bash` - a Bash library for [Redis](https://redis.io/) containing some useful shell-functions
2. `redis-cli` - an executable Bash script implementing an interactive Redis console
3. `redis-pool` - a connection pool for Redis

# Feature set

Redis request-response mode is fully supported.

Two other Redis features, viz.  pipelining and push protocol (such as used by commands: SUBSCRIBE, MONITOR etc.) are not supported yet, but can be implemented easily using the functions defined in `redis.bash` (see [below](#connection-pool) for pub-sub example).

# Library usage

To use the library functions in your Bash script, source the library first 

```bash
source <path to redis.bash>
```

Then, create a session using 

```bash
redis_connect [-h host] [-p port] [-a passwd] [-d database] [-t timeout in seconds]
```

Instead of using options, the host, port, password, database and timeout can also be provided using the respective environment variables: `REDIS_HOST`, `REDIS_PORT`, `REDIS_AUTH`, `REDIS_DB`, `REDIS_TIMEOUT`. The timeout is the interval used by the *automatic keepalive service*. If keepalive is not required, specify a 0s timeout. The defaults are- Host: localhost ; Port: 6379 ; DB: 0 ; Timeout: 300s.

To execute a single [Redis command](https://redis.io/commands/) in the server, and get its corresponding response, run 

```bash
redis_exec <commmand>
```

This sends the command to the server and then prints the server response to stderr or stdout, depending on whether the server response data-type (RESP) is "Error" or not. The rather trivial OK and PONG responses are not printed for redirected stdout, for developer convenience. `redis_exec` returns after reading exactly one complete RESP response from the server. The read has a 1 second timeout. If reading from or sending the command to the server fails, `redis_exec` assumes that the server got disconnected and tries to reconnect and resend the command automatically.

To end session with the server, simply

```bash
redis_disconnect
```

#### <u>Low level tasks:</u>

`redis_read [-t <timeout>]`: for parsing RESP

`redis_rep [-t <timeout>] [-n N]`: for reading N complete RESP responses and printing the values at stdout or stderr based on the RESP data-type(s).

See documentation in `redis.bash` for details.

# Demo / Example

Checkout the code in `redis-cli` . It uses the client-library only.

# Connection pool

Simple example using Unix sockets. For TCP sockets, replace `path/socket` with port number and remove the `-U` flag in `nc`:

1. In one terminal :

   ```bash
   ./redis-pool -n <max connections> -h <host> -p <port> -a <pass> path/socket
   ```

2. In another terminal: 

   ```bash
   . redis.bash # In order to define redis_rep
   echo -e "set foo bar\nget foo" | nc -N -U path/socket | redis_rep -n 2
   echo "subscribe channel" | nc -U path/socket | redis_rep -n 0
   ```

3. In still another terminal: 

   ```bash
   ./redis-cli
   localhost:port_db$ publish channel hello
   # Check now if you got the message in the second terminal
   ```

**Note:** We use `echo` with the Redis commands instead of `printf` or `echo -n`. The pool transforms trailing LF to CRLF before sending each inline command to the server. 

# Alternative(s)

https://redis.io/clients#bash

# Feedback, feature requests, bug report

Create an issue at the [project repository](https://github.com/SomajitDey/redis-client) or [write to me](mailto:dey.somajit@gmail.com). 

If you like this project, please consider giving it a star at [GitHub](https://github.com/SomajitDey/redis-client) to encourage me.

# Contribution

PRs are welcome. Please follow this minimal style guide when contributing:

- No camelCase. Only under_scores.
- Do, If, Case and For constructs as in `redis.bash`

Also put your name and email id in the comments section of your code-block.

If you cannot submit a PR at [GitHub](https://github.com/SomajitDey/redis-client), feel free to send me your patch over [email](mailto:dey.somajit@gmail.com). Just mention the Git commit hash in the [project repository](https://github.com/SomajitDey/redis-client) to which the patch should be applied.

**Open issue:** Make the docs better.

# Acknowledgements

TY: @[zuiderkwast](https://github.com/zuiderkwast)

# License

GNU Lesser General Public License - 2.1

Copyright (C) Somajit Dey, 2021
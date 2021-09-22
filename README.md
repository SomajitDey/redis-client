# Redis Client (Bash)

This project consists of 

1. `redis.bash` - a Bash library for [Redis](https://redis.io/) containing some useful shell-functions
2. `redis-cli` - an executable Bash script implementing an interactive Redis console
3. `redis-pool` - a [connection pool](https://en.wikipedia.org/wiki/Connection_pool) for Redis

# Library usage

1. To use the library functions in your Bash script, source the library first: `source <path to redis.bash>`

2. Then, create a session using 

   ```bash
   redis_connect [-h host] [-p port] [-a passwd] [-d database] [-t timeout in seconds]
   ```

   Instead of using options, the host, port, password, database and timeout can also be provided using the respective environment variables: `REDIS_HOST`, `REDIS_PORT`, `REDIS_AUTH`, `REDIS_DB`, `REDIS_TIMEOUT`. The timeout is the interval used by the *automatic keepalive service*. If keepalive is not required, specify a 0s timeout. The defaults are - Host: localhost ; Port: 6379 ; DB: 0 ; Timeout: 300s.

3. To execute a single [Redis command](https://redis.io/commands/) in the server, and get its corresponding response, run: 

   ```bash
   redis_exec <commmand>
   
   # Example: redis_exec 'keys *'
   ```

    This sends the command to the server and then prints the server response to stderr or stdout, depending on whether the server response data-type (RESP) is "Error" or not. The rather trivial OK and PONG responses are not printed for redirected stdout, for developer convenience. `redis_exec` returns after reading exactly one complete RESP response from the server. The read has a 1 second timeout. If reading from or sending the command to the server fails, `redis_exec` assumes that the server got disconnected and tries to reconnect and resend the command automatically. 

   **Note:** If you forget to do `redis_connect` (step 1 above), then `redis_exec` will exit with error: `Failed to acquire lock 1`. In that case, simply do step 1 and then retry `redis_exec`.

4. To end session with the server, simply do: `redis_disconnect`

### Low level tasks

`redis_read [-t <timeout>]`: for parsing RESP

`redis_rep [-t <timeout>] [-n N]`: for reading N complete RESP responses and printing the values at stdout or stderr based on the RESP data-type(s); N=0 implies an infinite reading loop useful for reading push messages.

See documentation in `redis.bash` for details.

### Demo / Example

Checkout the code in `redis-cli` . It uses the client-library only.

# CLI console

`./redis-cli -h <host> -p <port> -a <passwd> -t <idle timeout s> -d <database no.>`

To quit, enter any of the following: `q` , `exit` , `quit` (case-insensitive)

**Note**: If subscribed to push messages with `(P)SUBSCRIBE channel` or `MONITOR`, simply do `Ctrl-C` (i.e. ^C) followed by `Enter` to return to the normal interactive mode, i.e. get the command prompt back.

# Connection pool

`redis-pool` offers simple connection pooling with support for both Unix domain and TCP sockets. The local socket serves as a proxy for the remote Redis server. If the number of concurrent connections/requests to this proxy is more than what the server can support, the excess requests will be put on hold (i.e. blocking) and served whenever a spot opens up.

Following are simple examples using Unix domain sockets. For using TCP ports instead, simply replace `path/socket` with the port number and remove the `-U` flag in `nc`:

1. In one terminal :

   ```bash
   ./redis-pool -n <max connections> -h <host> -p <port> -a <pass> path/socket
   ```

2. In another terminal: 

   ```bash
   . redis.bash # In order to define redis_rep
   
   # Pipelining 2 commands in one go
   echo -e "set foo bar\nget foo" | nc -N -U path/socket | redis_rep -n 2
   
   # Activating the push protocol: pub-sub
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

https://github.com/caquino/redis-bash

# Feedback, feature requests, bug report

Create an issue at the [project repository](https://github.com/SomajitDey/redis-client) or [write to me](mailto:dey.somajit@gmail.com). 

If you like this project, please consider giving it a star at [GitHub](https://github.com/SomajitDey/redis-client) to encourage me.

# Contribution

PRs are welcome. Please follow this minimal style guide when contributing:

- No camelCase. Only under_scores.
- Do, If, Case and For constructs as in `redis.bash`

Also put your name and email id in the comments section of your code-block.

If you cannot submit a PR at [GitHub](https://github.com/SomajitDey/redis-client), feel free to send me your patch over [email](mailto:dey.somajit@gmail.com). Just mention the Git commit hash in the [project repository](https://github.com/SomajitDey/redis-client) to which the patch should be applied.

**Open issue:** Making the docs better.

# Support / Sponsor

[![Sponsor](https://www.buymeacoffee.com/assets/img/custom_images/yellow_img.png)](https://buymeacoffee.com/SomajitDey)

# Acknowledgements

TY: @[zuiderkwast](https://github.com/zuiderkwast)

# License

GNU Lesser General Public License - 2.1

Copyright (C) Somajit Dey, 2021
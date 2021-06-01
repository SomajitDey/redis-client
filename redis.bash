# REDIS Client Library for Bash
# Ref: https://redis.io/topics/protocol
# Inspiration: https://github.com/crypt1d/redi.sh
############################################################################################################

# Contributor(s) List:
# Somajit Dey <dey.somajit@gmail.com>
############################################################################################################

# Design-Philosophy:
#
# Ingredients - Best effort towards using Bash native functionalities only. Yet can't escape using flock.
# The closest Bash implementation of flock is `marker=${LOCK:=set}` which checks if LOCK is set and sets it 
# if it isn't - all atomically (perhaps).
#
# Codec - Only the RESP parser is implemented. This is to decode the REDIS server response. Encoding client
# command to RESP is not necessary because REDIS server is smart enough to understand it as inline-commands.
# Care must however be taken to put in the trailing CRLF [Ref: https://redis.io/topics/protocol#inline-commands].
#
# Naming - The RESP parser is called `redis_read` in view of its similarity to the `read` command in Unix.
#
# Locks - redis_exec and redis_connect are critical sections. The user and the background keepalive usually
# compete for redis_exec. In case server is disconnected, redis_exec calls redis_connect. So, sometimes, they
# compete for redis_connect as well. Hence, distributed locking is implemented - 2 locks in redis_exec, 1 distributed
# between redis_disconnect and redis_connect. For simplicity, locks are non-blocking.
#############################################################################################################

# TODO: Support for RESP push protocol: redis_pipeline & redis_subscribe

#############################################################################################################

redis_read(){
  # Brief: Read a complete response from REDIS server, parse, then set 2 shell-variables with the response data-type and value.
  # Usage: redis_read [-t <timeout>] [name]
  # The read values are stored in the `name` variable provided. If `name` is absent, REDIS_REPLY is set instead.
  # Note the similarity with the `read` builtin of Bash.
  # The env variable REDIS_TYPE is set with the data-type.
  # An empty REDIS_TYPE element implies a "Null bulk string" or "Null array" data-type.
  # Readings are faithful, i.e. backslashes are not escaped.

  # RESP data-types abbr:
  # simple-string=sstr; error=err; integer=int; bulk-string=bstr; arr=arr; null-bulk-stringor array=null

  # REDIS_TYPE and REDIS_REPLY:
  # These are always Bash array variables for simplicity. For any data-type except arr, their lengths are <=1.
  # Note that the simple command: `variable="${REDIS_REPLY}"` actually sets `variable` with `${REDIS_REPLY[0]}`
  # For arr data-types, REDIS_TYPE and REDIS_REPLY are filled with the type and value of the corresponding elements in arr.
  # For example: Reading *2\r\n:1\r\n+OK\r\n  would set REDIS_TYPE=(int sstr) and REDIS_REPLY=(1 OK)

  local -x OPTIND=1
  while getopts t: option;do
    case "${option}" in
      t) local tmout="-t ${OPTARG}";;
    esac
  done
  
  local name="${!OPTIND:-REDIS_REPLY}"
  eval unset "${name}"[@] REDIS_TYPE[@] # eval makes sure $name is expanded before shell runs the command
  eval declare -gxa "${name}" REDIS_TYPE # Making it array (-a) to avoid 'variable not array' errors for prefix='*' later
  
  local prefix
  read -r -n1 ${tmout} prefix || return 1
  case "${prefix}" in
    '+')
        REDIS_TYPE="sstr"
        ;;
    '-')
        REDIS_TYPE="err"
        ;;
    ':')
        REDIS_TYPE="int"
        ;;     
    '$')
        REDIS_TYPE="bstr"
        ;;
  esac
  
  read_simplest(){
    read -r -d $'\r\n' "${name}" && read # Last read takes out the \n from \r\n
  }
  
  read_simplest
  
  case "${prefix}" in
    '$')
        local nbytes="${!name}" # From the last read_simplest
        if ((nbytes!=-1));then
          read -r -d $'\r\n' -N "${nbytes}" "${name}" && read
        else
          REDIS_TYPE=
          eval "${name}="
        fi
        ;;
    '*')
        local nelements="${!name}" # From the last read_simplest
        if ((nelements!=-1));then
          for i in $(seq "${nelements}");do
            local index="$((i-1))"
            redis_read
            local proxy_type[index]="${REDIS_TYPE}"
            local proxy_reply[index]="${REDIS_REPLY}"
          done
          REDIS_TYPE=(${proxy_type[@]})
          eval "${name}=(${proxy_reply[@]})"
        else
          REDIS_TYPE=
          eval "${name}="
        fi
        ;;
  esac  
}; export -f redis_read

redis_rep(){
  # Brief: REP - Read-Evaluate-Print.
  # Read one complete RESP response from stdin, evaluate data-type & print non-trivial responses.
  # OK and PONG are not printed as these are trivial. Null bulk-string is printed as NuLL$'\a'. Err printed at stderr.
  # Usage: redis_rep
  # Exit-code:
  # 0 - successful read and data-type other than Err
  # 1 - successful read and data-type: Err
  # 22 - unsuccessful read; server disconnected
  
  redis_read -t 1 || return 22
  local array_size="${#REDIS_TYPE[@]}"
  if ((array_size<=1)); then
    case "${REDIS_TYPE}" in
      err) echo "${REDIS_REPLY}" >&2; return 1;;
      int | bstr) echo "${REDIS_REPLY}";;
      '') echo -e NuLL\\a;;
      sstr) [[ "${REDIS_REPLY}" =~ ^(OK|PONG)$ ]] || echo "${REDIS_REPLY}";;
    esac
  else
    for i in "${array_size}"; do
      [[ -z "${REDIS_TYPE[array_size-1]}" ]] && REDIS_REPLY[array_size-1]=NuLL$'\a'
    done
    echo "${REDIS_REPLY[@]}"
  fi
}; export -f redis_rep

redis_connect(){
  # Brief: Connect to REDIS server and log-in with password, if any. Set up keepalive service.
  # Usage: redis_connect [-h <host>] [-p <port>] [-a <passwd>] [-t <idle timeout s>] [-d <database no.>]
  # These env vars may also be used instead of the parameters:
  #   REDIS_HOST, REDIS_PORT, REDIS_AUTH, REDIS_TIMEOUT, REDIS_DB
  # Timeout: arg of -t or REDIS_TIMEOUT gives the interval to ping REDIS server for keeping connection alive
  # Exit-code:
  #   0 : Success
  #  22 : Failed to connect to server
  #  21 : Failed to connect to given database
  #  20 : Failed to log-in with given passwd
  #   1 : wrong option detected

  redis_disconnect

  declare -xg REDIS_HOST="${REDIS_HOST:-localhost}"
  declare -xg REDIS_PORT="${REDIS_PORT:-6379}"
  declare -xg REDIS_AUTH REDIS_DB
  declare -xg REDIS_TIMEOUT="${REDIS_TIMEOUT:-300}"
  declare -xg REDIS_FD="$(python3 -c 'import random; print(random.randint(10, 100))')"

  local -x OPTIND=1
  while getopts ':h:p:a:t:d:' opt;do
    case "${opt}" in
      h) REDIS_HOST="${OPTARG}";;
      p) REDIS_PORT="${OPTARG}";;
      a) REDIS_AUTH="${OPTARG}";;
      t) REDIS_TIMEOUT="${OPTARG}";;
      d) REDIS_DB="${OPTARG}";;
      *) echo "Usage: ${0} -h <host> -p <port> -a <passwd> -t <idle timeout s> -d <database no.>" >&2; return 1;;
    esac
  done

  eval "exec ${REDIS_FD}<>/dev/tcp/${REDIS_HOST}/${REDIS_PORT}" || return 22

  declare -xg REDIS_LOCK="$(mktemp -u /tmp/redis_${BASHPID}_XXXXX.lock)" # Unlock 1. Note the -u. This is not unsafe as ${BASHPID} is there.

  if [[ -n "${REDIS_AUTH}" ]]; then
    redis_exec "AUTH ${REDIS_AUTH}" || { redis_disconnect; return 20;}
  fi

  if [[ -n "${REDIS_DB}" ]]; then
    redis_exec "SELECT ${REDIS_DB}" || { redis_disconnect; return 21;}
  fi

  # Setup keepalive
  if ((REDIS_TIMEOUT > 0));then
    trap "redis_keepalive" ALRM
    kill -ALRM ${BASHPID}
  fi
}; export -f redis_connect

redis_keepalive(){
  # Brief: Keepalive connection to REDIS server. To be run by redis_connect as SIGALRM handler.
  # Usage: redis_keepalive
  # Exit-code: Either 0 (when success) or 1 (on failure).

  redis_exec 'PING'
  case "$?" in
    20|21|22) return 1;;
    *) (sleep "${REDIS_TIMEOUT}" && kill -ALRM ${BASHPID})& declare -xg REDIS_KA=${!};;
  esac
} &>/dev/null; export -f redis_keepalive

redis_disconnect(){
  # Brief: Disconnect from REDIS server; i.e. end session and cleanup.
  # Usage: redis_disconnect
  # Exit-code: 0

  [[ -n "${REDIS_KA}" ]] && kill -KILL "${REDIS_KA}" ; unset REDIS_KA # Kill keepalive proc in bg
  trap - ALRM # Reset trap
  if [[ -n "${REDIS_FD}" ]]; then
    eval "exec ${REDIS_FD}<&-"
    eval "exec ${REDIS_FD}>&-"
  fi
  local unlink_me="${REDIS_LOCK}"
  unset REDIS_FD REDIS_LOCK # Lock 1
  rm -f "${unlink_me}" # More for cleanup than for unlock 2
} &>/dev/null; export -f redis_disconnect

redis_exec(){
  # Brief: Execute REDIS command passed as parameters and print non-trivial server response, if any.
  #   OK and PONG are not printed. Null bulk-string is printed as NuLL$'\a'. Err printed at stderr.
  # Usage: redis_exec <command>
  # Example:
  #  redis_exec GET key
  #  redis_exec set key value
  #  redis_exec 'keys *' # Without the quotes here, * would be treated as glob and expanded by shell
  # Exit-code:
  #  0 : Success
  #  1 : Error response by REDIS server
  # 22 : Server not connected. Reconnect.
  # 23 : Failed to acquire lock.
  
  local cmd="${@}"

  if [[ -n "${REDIS_LOCK}" ]]; then # Check Lock 1 : Set or unset
    trap 'rm -f ${REDIS_LOCK}' return # Unlock 2 trap. Note that ${REDIS_LOCK} needs to be expanded when handler is executed
    [[ -e "${REDIS_LOCK}" ]] && { echo "Failed to acquire lock 2" >&2; return 23;} # Check Lock 2 : Exists or not
  else 
    echo "Failed to acquire lock 1" >&2
    return 23
  fi

  (
  flock -n 9 || { echo "Failed to acquire lock 3" >&2; exit 23;} # Check Lock 3 : Atomically locked or not

  if [[ -n "${REDIS_FD}" ]] && [[ -e /dev/fd/"${REDIS_FD}" ]]; then
    while redis_read -t 0.001; do :;done <& "${REDIS_FD}" # Discard response if any from a previous command
    echo -n "${cmd}"$'\r\n' >& "${REDIS_FD}" || exit 22 # Inline command: note trailing CRLF
    redis_rep <& "${REDIS_FD}"
  else
#    echo "No TCP connection to the REDIS server - ${REDIS_HOST}:${REDIS_PORT}" >&2
    exit 22
  fi
  )9>"${REDIS_LOCK:-/dev/null}"

  local exitcode=${?}
  if ((exitcode == 22)); then
    redis_connect && redis_exec "${cmd}" # Reconnect when existing connection closes
  else
    return "${exitcode}"
  fi
}; export -f redis_exec

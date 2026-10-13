# nginx-sflow-module

[![Build & Test][build-test-badge]][build-test-link]
[![FreeBSD][freebsd-badge]][freebsd-link]
[![Datagrams][datagrams-badge]][datagrams-link]
[![A/UBSan][sanitizers-badge]][sanitizers-link]
[![Valgrind][valgrind-badge]][valgrind-link]
[![Reload][reload-badge]][reload-link]
[![CodeQL][codeql-badge]][codeql-link]
[![Lint][lint-badge]][lint-link]

[build-test-badge]: https://github.com/sysadmin-labs/nginx-sflow-module/actions/workflows/build-test.yml/badge.svg
[build-test-link]: https://github.com/sysadmin-labs/nginx-sflow-module/actions/workflows/build-test.yml
[freebsd-badge]: https://github.com/sysadmin-labs/nginx-sflow-module/actions/workflows/freebsd.yml/badge.svg
[freebsd-link]: https://github.com/sysadmin-labs/nginx-sflow-module/actions/workflows/freebsd.yml
[datagrams-badge]: https://github.com/sysadmin-labs/nginx-sflow-module/actions/workflows/datagrams.yml/badge.svg
[datagrams-link]: https://github.com/sysadmin-labs/nginx-sflow-module/actions/workflows/datagrams.yml
[sanitizers-badge]: https://github.com/sysadmin-labs/nginx-sflow-module/actions/workflows/sanitizers.yml/badge.svg
[sanitizers-link]: https://github.com/sysadmin-labs/nginx-sflow-module/actions/workflows/sanitizers.yml
[valgrind-badge]: https://github.com/sysadmin-labs/nginx-sflow-module/actions/workflows/valgrind.yml/badge.svg
[valgrind-link]: https://github.com/sysadmin-labs/nginx-sflow-module/actions/workflows/valgrind.yml
[reload-badge]: https://github.com/sysadmin-labs/nginx-sflow-module/actions/workflows/reload.yml/badge.svg
[reload-link]: https://github.com/sysadmin-labs/nginx-sflow-module/actions/workflows/reload.yml
[codeql-badge]: https://github.com/sysadmin-labs/nginx-sflow-module/actions/workflows/codeql.yml/badge.svg
[codeql-link]: https://github.com/sysadmin-labs/nginx-sflow-module/actions/workflows/codeql.yml
[lint-badge]: https://github.com/sysadmin-labs/nginx-sflow-module/actions/workflows/lint.yml/badge.svg
[lint-link]: https://github.com/sysadmin-labs/nginx-sflow-module/actions/workflows/lint.yml

Random-sampling request monitoring for nginx, as sFlow.  A sampled request
leaves the server as a UDP datagram carrying the method, the status, the
URI, the host, the referer, the user agent, the mime type, the byte counts,
the duration and both ends of the socket.  Alongside it the agent sends
counters: requests per method and per status class, for every worker.

It is built for the case where logs do not scale: sampling one request in a
thousand costs the same per request whether the server does ten a second or
ten thousand, and the collector sees the whole farm rather than a file per
host.

## Directives

### sflow

**syntax:** `sflow on | off`

**context:** http, server, location, if in location, limit_except

Whether requests here are sampled and counted.

```nginx
http {
    sflow on;

    server {
        location /health {
            sflow off;
        }
    }
}
```

`off` stops both the sampling and the counting for that place -- the counters
only ever count what sampling would have looked at.

A location may turn sampling back `on` where something further out turned it
off.

### sflow\_config\_file

**syntax:** `sflow_config_file <path>`

**default:** `/etc/hsflowd.auto`

**context:** http

Where to read the sFlow configuration from.  One file per server, and the
path is read again on every tick, so changing it does not need a reload.

## Configuration

The sampling rate and the collector do not come from the nginx
configuration.  They come from a file the agent re-reads once a second,
which is how a whole farm gets its rate changed from one place without a
reload anywhere:

```
rev_start=1
sampling=1000
polling=20
header=128
agentIP=10.0.0.150
collector=10.0.0.1 6343
rev_end=1
```

`rev_start` and `rev_end` have to match; a file being written is a file
whose two revisions differ, and the agent then keeps the configuration it
had.  `sampling=1000` is one request in a thousand, `polling=20` sends the
counters every twenty seconds, and `agentIP` is the address the collector
will see this server as -- that one is required, a file without it is
refused with a line in the error log.  `sampling.http` and `polling.http` override
`sampling` and `polling` for this module alone.

Until the file names a rate the module samples nothing, so an nginx with
`sflow on` and no configuration file sends no datagrams and serves requests
exactly as it would without the module.

The usual way to write that file is to let
[hsflowd](https://github.com/sflow/host-sflow) do it, which is also what
sends the host's own counters.

## Reading what arrives

[sflowtool](https://github.com/sflow/sflowtool) prints it:

```sh
sflowtool                 # everything, as text
sflowtool -H              # the HTTP samples, as a common log file
```

`ci/datagrams.sh` in this repository decodes it too, in about a hundred
lines of Perl, which is a shorter read if the question is what the module
actually emits.

## Building

```sh
./configure --add-module=/path/to/nginx-sflow-module
```

or as a loadable module:

```sh
./configure --with-compat --add-dynamic-module=/path/to/nginx-sflow-module
```

```nginx
load_module modules/ngx_http_sflow_module.so;
```

A package whose prefix is not `/` can move the default configuration path
without patching the source:

```sh
./configure --add-module=... \
    --with-cc-opt='-DSFWB_DEFAULT_CONFIGFILE=\"/usr/local/etc/hsflowd.auto\"'
```

## Testing

```sh
ci/build.sh 1.30.5 /tmp/nginx-sflow
TEST_NGINX_BINARY=/tmp/nginx-sflow/sbin/nginx prove -r t/
ci/datagrams.sh /tmp/nginx-sflow/sbin/nginx
```

`t/` says what a server does while the module is in it: which
configurations are accepted, which are refused, and that requests are
served unchanged.  `ci/datagrams.sh` is the one that looks at the product --
it starts a collector, makes requests, and decodes what arrives.  A module
that samples nothing passes the first and fails the second.

## License

The module is InMon Corporation's, under the InMon sFlow licence; the
scaffolding around it is BSD 2-Clause.  Both texts, and what is worth
knowing about the first, are in [LICENSE](LICENSE).

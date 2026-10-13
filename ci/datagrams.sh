#!/bin/sh
#
# Catch what the module actually puts on the wire and take it apart.
#
# This is the only check that looks at the product of this module.  t/ can
# say that a configuration is accepted or refused and that requests are
# still served, which is worth knowing and is not the same thing: a module
# that sends nothing at all passes every one of those blocks.
#
# The decoder is written against src/ngx_http_sflow.h and the encoder in
# src/ngx_http_sflow_api.c rather than against a tool, so that it says what
# this module emits and not what some other sFlow agent does.
#
# usage: ci/datagrams.sh <nginx binary>
#
# Set DATAGRAMS_LOAD_MODULE to the path of ngx_http_sflow_module.so to test
# a loadable build.

set -eu

NGINX=${1:?path to the nginx binary missing}
WORK=${CI_WORK:-$(cd "$(dirname "$0")/.." && pwd)/ci-work}/datagrams
PORT=${DATAGRAMS_PORT:-18530}
CPORT=${DATAGRAMS_COLLECTOR_PORT:-18531}

command -v curl > /dev/null || { echo "curl(1) is needed" >&2; exit 2; }
command -v perl > /dev/null || { echo "perl(1) is needed" >&2; exit 2; }

rm -rf "$WORK"
mkdir -p "$WORK/conf" "$WORK/logs" "$WORK/out" "$WORK/tmp"

fail=0
note() {
	echo "  $1" >&2
	fail=1
}

# ------------------------------------------------------------- the collector

cat > "$WORK/collector.pl" <<'PERL'
use strict;
use warnings;
use IO::Socket::INET;

# One line per sample, so the shell can grep for what it expects.  The
# layout comes from src/ngx_http_sflow_api.c: a version 5 datagram header,
# then samples, and SFL_USE_32BIT_INDEX is not defined anywhere in this
# repository, so the sample tags are 1 and 2 with a packed source id and not
# the expanded 3 and 4.  Both are handled anyway -- a decoder that only
# understands the shape it expects proves nothing when the shape changes.

my $port = shift or die "port missing\n";
my $srv = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => $port,
                                Proto => 'udp', ReuseAddr => 1)
    or die "bind: $!\n";

$| = 1;

sub u32 { my ($b, $o) = @_; return unpack('N', substr($$b, $$o, 4)) , $$o += 4; }

sub get32 {
    my ($b, $o) = @_;
    die "short datagram\n" if $$o + 4 > length($$b);
    my $v = unpack('N', substr($$b, $$o, 4));
    $$o += 4;
    return $v;
}

sub get64 {
    my ($b, $o) = @_;
    my $hi = get32($b, $o);
    my $lo = get32($b, $o);
    return ($hi * 4294967296) + $lo;
}

sub getstr {
    my ($b, $o) = @_;
    my $len = get32($b, $o);
    my $s = substr($$b, $$o, $len);
    $$o += ($len + 3) & ~3;      # XDR pads to four bytes
    return $s;
}

sub esc {
    my $s = shift;
    $s = '-' if !defined $s || $s eq '';
    $s =~ s/([^\x21-\x7e]|,)/sprintf('%%%02x', ord($1))/ge;
    return $s;
}

while (1) {
    my $pkt;
    $srv->recv($pkt, 65535) or next;
    my $o = 0;

    my $version = get32(\$pkt, \$o);
    print "BAD version=$version\n" and next if $version != 5;

    my $addrtype = get32(\$pkt, \$o);
    my $agent;
    if ($addrtype == 1) {
        $agent = join '.', unpack('C4', substr($pkt, $o, 4));
        $o += 4;
    } elsif ($addrtype == 2) {
        $agent = unpack('H*', substr($pkt, $o, 16));
        $o += 16;
    } else {
        print "BAD addrtype=$addrtype\n";
        next;
    }

    my $subid    = get32(\$pkt, \$o);
    my $seqno    = get32(\$pkt, \$o);
    my $uptime   = get32(\$pkt, \$o);
    my $nsamples = get32(\$pkt, \$o);

    print "DATAGRAM agent=$agent subid=$subid seq=$seqno uptime=$uptime samples=$nsamples len="
        . length($pkt) . "\n";

    for (my $s = 0; $s < $nsamples; $s++) {
        my $tag = get32(\$pkt, \$o);
        my $len = get32(\$pkt, \$o);
        my $end = $o + $len;

        if ($tag == 1 || $tag == 3) {
            my $seq = get32(\$pkt, \$o);
            my ($dsclass, $dsindex);
            if ($tag == 3) {
                $dsclass = get32(\$pkt, \$o);
                $dsindex = get32(\$pkt, \$o);
            } else {
                my $src = get32(\$pkt, \$o);
                $dsclass = $src >> 24;
                $dsindex = $src & 0xffffff;
            }
            my $rate  = get32(\$pkt, \$o);
            my $pool  = get32(\$pkt, \$o);
            my $drops = get32(\$pkt, \$o);
            get32(\$pkt, \$o) for (1 .. ($tag == 3 ? 4 : 2));   # input, output
            my $nelem = get32(\$pkt, \$o);

            print "FLOW seq=$seq dsclass=$dsclass dsindex=$dsindex rate=$rate"
                . " pool=$pool drops=$drops elements=$nelem\n";

            for (my $e = 0; $e < $nelem; $e++) {
                my $etag = get32(\$pkt, \$o);
                my $elen = get32(\$pkt, \$o);
                my $eend = $o + $elen;

                if ($etag == 2206) {
                    my $method    = get32(\$pkt, \$o);
                    my $protocol  = get32(\$pkt, \$o);
                    my $uri       = getstr(\$pkt, \$o);
                    my $host      = getstr(\$pkt, \$o);
                    my $referrer  = getstr(\$pkt, \$o);
                    my $useragent = getstr(\$pkt, \$o);
                    my $xff       = getstr(\$pkt, \$o);
                    my $authuser  = getstr(\$pkt, \$o);
                    my $mimetype  = getstr(\$pkt, \$o);
                    my $reqbytes  = get64(\$pkt, \$o);
                    my $respbytes = get64(\$pkt, \$o);
                    my $us        = get32(\$pkt, \$o);
                    my $status    = get32(\$pkt, \$o);

                    print "HTTP method=$method protocol=$protocol status=$status"
                        . " uri=" . esc($uri) . " host=" . esc($host)
                        . " referrer=" . esc($referrer)
                        . " useragent=" . esc($useragent)
                        . " xff=" . esc($xff)
                        . " authuser=" . esc($authuser)
                        . " mimetype=" . esc($mimetype)
                        . " reqbytes=$reqbytes respbytes=$respbytes us=$us\n";

                } elsif ($etag == 2100) {
                    my $proto = get32(\$pkt, \$o);
                    my $lip = join '.', unpack('C4', substr($pkt, $o, 4)); $o += 4;
                    my $rip = join '.', unpack('C4', substr($pkt, $o, 4)); $o += 4;
                    my $lport = get32(\$pkt, \$o);
                    my $rport = get32(\$pkt, \$o);
                    print "SOCKET4 proto=$proto local=$lip:$lport remote=$rip:$rport\n";

                } else {
                    print "ELEMENT tag=$etag len=$elen\n";
                }

                $o = $eend;
            }

        } elsif ($tag == 2 || $tag == 4) {
            my $seq = get32(\$pkt, \$o);
            if ($tag == 4) { get32(\$pkt, \$o); get32(\$pkt, \$o); }
            else           { get32(\$pkt, \$o); }
            my $nelem = get32(\$pkt, \$o);
            print "COUNTERS seq=$seq elements=$nelem\n";

            for (my $e = 0; $e < $nelem; $e++) {
                my $etag = get32(\$pkt, \$o);
                my $elen = get32(\$pkt, \$o);
                my $eend = $o + $elen;

                if ($etag == 2201) {
                    my @names = qw(options get head post put delete trace
                                   connect other s1xx s2xx s3xx s4xx s5xx
                                   sother);
                    my @v;
                    push @v, get32(\$pkt, \$o) for (1 .. 15);
                    print "HTTPCOUNTERS "
                        . join(' ', map { "$names[$_]=$v[$_]" } 0 .. 14) . "\n";
                } else {
                    print "COUNTERBLOCK tag=$etag len=$elen\n";
                }

                $o = $eend;
            }

        } else {
            print "SAMPLE tag=$tag len=$len\n";
        }

        $o = $end;
    }
}
PERL

perl "$WORK/collector.pl" "$CPORT" > "$WORK/out/samples.txt" 2>"$WORK/out/collector.err" &
collector_pid=$!
sleep 1

cleanup() {
	kill "$collector_pid" 2>/dev/null || true
	[ -f "$WORK/logs/nginx.pid" ] &&
		kill -QUIT "$(cat "$WORK/logs/nginx.pid")" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ------------------------------------------------- what hsflowd would write

# sampling=1 means every request, which is what a test wants and no
# production site does.  polling=1 so the counters arrive within a second
# instead of within a minute.
cat > "$WORK/hsflowd.auto" <<EOF
rev_start=1
sampling=1
polling=1
header=128
agentIP=127.0.0.1
collector=127.0.0.1 $CPORT
rev_end=1
EOF

# --------------------------------------------------------------- the nginx

ngx_user=
if [ "$(id -u)" = 0 ]; then
	ngx_user="user root $(id -gn);"
fi

ngx_load=
if [ -n "${DATAGRAMS_LOAD_MODULE:-}" ]; then
	ngx_load="load_module $DATAGRAMS_LOAD_MODULE;"
fi

cat > "$WORK/conf/nginx.conf" <<EOF
$ngx_load
$ngx_user
daemon on;
master_process on;
worker_processes 1;
pid $WORK/logs/nginx.pid;
error_log $WORK/logs/error.log info;
events { worker_connections 64; }
http {
    access_log off;
    client_body_temp_path $WORK/tmp/cb;
    fastcgi_temp_path $WORK/tmp/fc;
    uwsgi_temp_path $WORK/tmp/uw;
    scgi_temp_path $WORK/tmp/sc;
    default_type text/plain;

    sflow on;
    sflow_config_file $WORK/hsflowd.auto;

    server {
        listen 127.0.0.1:$PORT;

        location = /sampled {
            return 200 'sampled';
        }

        location = /quiet {
            sflow off;
            return 200 'quiet';
        }

        location = /gone {
            return 404 'gone';
        }
    }
}
EOF

"$NGINX" -t -c "$WORK/conf/nginx.conf" -p "$WORK" > "$WORK/out/t.log" 2>&1 ||
	{ cat "$WORK/out/t.log"; exit 1; }
"$NGINX" -c "$WORK/conf/nginx.conf" -p "$WORK"

# The agent picks the configuration up on a tick, one second apart, and the
# first tick also has to get past "no configuration yet".
sleep 3

# ---------------------------------------------------------------- the cases

echo "--- ten sampled requests at sampling=1 ---"
i=0
while [ "$i" -lt 10 ]; do
	curl -s --max-time 5 "http://127.0.0.1:$PORT/sampled" -o /dev/null || true
	i=$((i + 1))
done

echo "--- a POST, a 404, and five requests to a location with sflow off ---"
curl -s --max-time 5 -X POST --data 'x=1' "http://127.0.0.1:$PORT/sampled" -o /dev/null || true
curl -s --max-time 5 "http://127.0.0.1:$PORT/gone" -o /dev/null || true
i=0
while [ "$i" -lt 5 ]; do
	curl -s --max-time 5 "http://127.0.0.1:$PORT/quiet" -o /dev/null || true
	i=$((i + 1))
done

# Samples leave with the next tick, counters once polling says so.
sleep 4

S="$WORK/out/samples.txt"

echo "--- datagrams arrived at all ---"
if [ -s "$S" ] && grep -q '^DATAGRAM ' "$S"; then
	echo "  $(grep -c '^DATAGRAM ' "$S") datagrams, $(grep -c '^FLOW ' "$S") flow samples, $(grep -c '^COUNTERS ' "$S") counters samples"
else
	note "nothing arrived on the collector port"
	[ -s "$WORK/out/collector.err" ] && sed 's/^/  /' "$WORK/out/collector.err" >&2
	cat "$WORK/logs/error.log" >&2 || true
	exit 1
fi

echo "--- nothing the decoder could not read ---"
if grep -q '^BAD ' "$S"; then
	note "the collector could not make sense of a datagram:"
	grep '^BAD ' "$S" | sed 's/^/  /' >&2
else
	echo "  every datagram was version 5 with an address the header announced"
fi

echo "--- the agent is the address the configuration named ---"
if grep -q '^DATAGRAM agent=127\.0\.0\.1 ' "$S"; then
	echo "  agent=127.0.0.1"
else
	note "the agent address is not the configured one"
	grep -m1 '^DATAGRAM ' "$S" | sed 's/^/  /' >&2
fi

echo "--- one flow sample per sampled request, and none for the quiet one ---"
got=$(grep -c '^HTTP .* uri=/sampled ' "$S" || true)
if [ "$got" -ge 11 ]; then
	echo "  $got samples for /sampled, ten GETs and one POST"
else
	note "expected at least 11 samples for /sampled, got $got"
fi
if grep -q 'uri=/quiet' "$S"; then
	note "a location with \"sflow off\" was sampled anyway"
else
	echo "  /quiet produced none"
fi

echo "--- the sampling rate in the sample is the configured one ---"
if grep -q '^FLOW .* rate=1 ' "$S"; then
	echo "  rate=1"
else
	note "the flow samples do not carry rate=1"
	grep -m1 '^FLOW ' "$S" | sed 's/^/  /' >&2
fi

echo "--- method and status are what the request and the answer were ---"
if grep -q '^HTTP method=2 .* status=200 uri=/sampled ' "$S"; then
	echo "  GET /sampled: method=2, status=200"
else
	note "no GET sample with method=2 and status=200"
fi
if grep -q '^HTTP method=4 .* status=200 uri=/sampled ' "$S"; then
	echo "  POST /sampled: method=4"
else
	note "no POST sample with method=4"
fi
if grep -q '^HTTP .* status=404 uri=/gone ' "$S"; then
	echo "  GET /gone: status=404"
else
	note "no sample with status=404 for /gone"
fi

echo "--- the useragent travelled with it ---"
if grep -q '^HTTP .* useragent=curl' "$S"; then
	echo "  useragent starts with curl"
else
	note "the user agent did not make it into the sample"
	grep -m1 '^HTTP ' "$S" | sed 's/^/  /' >&2
fi

echo "--- the socket record names both ends ---"
if grep -q "^SOCKET4 proto=6 local=127\.0\.0\.1:$PORT " "$S"; then
	echo "  local=127.0.0.1:$PORT over tcp"
else
	note "no socket4 record naming the local port"
	grep -m1 '^SOCKET4 ' "$S" | sed 's/^/  /' >&2 || true
fi

echo "--- the counters count what went through ---"
if grep -q '^HTTPCOUNTERS ' "$S"; then
	last=$(grep '^HTTPCOUNTERS ' "$S" | tail -1)
	get=$(echo "$last" | sed -n 's/.* get=\([0-9]*\).*/\1/p')
	s2xx=$(echo "$last" | sed -n 's/.* s2xx=\([0-9]*\).*/\1/p')
	s4xx=$(echo "$last" | sed -n 's/.* s4xx=\([0-9]*\).*/\1/p')
	# Eleven GETs are counted: the ten to /sampled and the one to /gone.
	# The five to /quiet are not -- the handler returns on "sflow off"
	# before it reaches the counters, so that switch silences both the
	# sampling and the counting.
	if [ "${get:-0}" -ge 10 ] && [ "${s2xx:-0}" -ge 10 ] && [ "${s4xx:-0}" -ge 1 ]; then
		echo "  get=$get s2xx=$s2xx s4xx=$s4xx"
	else
		note "the counters do not add up: $last"
	fi
else
	note "no http counters block arrived"
fi

echo "--- the worker is still there ---"
alive=$(curl -s --max-time 5 "http://127.0.0.1:$PORT/sampled" || true)
if [ "$alive" = sampled ]; then
	echo "  it answers"
else
	note "the worker did not answer after all that"
fi

echo "--- nothing in the error log that should not be there ---"
if grep -E '\[alert\]|\[emerg\]|exited on signal' "$WORK/logs/error.log"; then
	note "the log carries an alert, an emerg or a worker that died"
else
	echo "  no alert, no emerg, no signal"
fi

exit $fail

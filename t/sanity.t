# vi:ft=perl
#
# What a server does while the module is in it.  There is no collector here
# -- ci/datagrams.sh is where the datagrams are caught and taken apart --
# so what these blocks are for is the other half: a module that samples
# requests must not change what the client gets, must not fall over when
# there is no configuration to sample by, and must not mind which method or
# status code came past.

use Test::Nginx::Socket 'no_plan';

repeat_each(2);

run_tests();

__DATA__

=== TEST 1: a request with sampling on
--- config
    sflow on;
    location = /t {
        return 200 'served';
    }
--- request
GET /t
--- response_body chop
served
--- no_error_log
[alert]
[emerg]



=== TEST 2: a request with sampling off
--- config
    sflow off;
    location = /t {
        return 200 'served';
    }
--- request
GET /t
--- response_body chop
served
--- no_error_log
[alert]
[emerg]



=== TEST 3: off for the server, on for one location
# The flag has three states for this: with a plain on/off flag the location
# could not win, because "nothing said here" and "off" would look the same.
--- config
    sflow off;
    location = /on {
        sflow on;
        return 200 'on';
    }
    location = /off {
        return 200 'off';
    }
--- request
GET /on
--- response_body chop
on
--- no_error_log
[alert]
[emerg]



=== TEST 4: a configuration file that is not there
# The agent reads it on a tick and keeps waiting if it is missing.  Nothing
# is sampled, and that is all that happens -- no error, and the request is
# served as if the module were not there.
--- http_config
    sflow_config_file /nonexistent/hsflowd.auto;
--- config
    sflow on;
    location = /t {
        return 200 'served';
    }
--- request
GET /t
--- response_body chop
served
--- no_error_log
[alert]
[emerg]



=== TEST 5: a configuration file that is there and says nothing
# An empty file is treated the same as a missing one, deliberately: a file
# being rewritten is briefly empty, and a monitoring agent that stops
# sampling for that moment is worse than one that keeps the rate it had.
#
# /dev/null rather than a file of our own, because a path cannot be built
# here: $TEST_NGINX_HTML_DIR is substituted from the environment and nothing
# defines it, and a relative path would be resolved against whatever
# directory prove was started from.  A file with real contents in it is
# ci/datagrams.sh's business, and that is where the samples are checked.
--- http_config
    sflow_config_file /dev/null;
--- config
    sflow on;
    location = /t {
        return 200 'served';
    }
--- request
GET /t
--- response_body chop
served
--- no_error_log
[alert]
[emerg]



=== TEST 6: a HEAD request
--- config
    sflow on;
    location = /t {
        return 200 'served';
    }
--- request
HEAD /t
--- error_code: 200
--- no_error_log
[alert]
[emerg]



=== TEST 7: a POST with a body
--- config
    sflow on;
    location = /t {
        return 200 'served';
    }
--- request
POST /t
a body that goes nowhere
--- response_body chop
served
--- no_error_log
[alert]
[emerg]



=== TEST 8: a status the module has a counter for
--- config
    sflow on;
    location = /t {
        return 404 'gone';
    }
--- request
GET /t
--- error_code: 404
--- response_body chop
gone
--- no_error_log
[alert]
[emerg]



=== TEST 9: a status outside the usual ranges
--- config
    sflow on;
    location = /t {
        return 599 'odd';
    }
--- request
GET /t
--- error_code: 599
--- no_error_log
[alert]
[emerg]



=== TEST 10: sampling on inside limit_except
--- config
    sflow on;
    location = /t {
        limit_except GET {
            sflow off;
        }
        return 200 'served';
    }
--- request
GET /t
--- response_body chop
served
--- no_error_log
[alert]
[emerg]



=== TEST 11: sampling off inside an if
--- config
    sflow on;
    location = /t {
        if ($arg_quiet) {
            sflow off;
        }
        return 200 'served';
    }
--- request
GET /t?quiet=1
--- response_body chop
served
--- no_error_log
[alert]
[emerg]



=== TEST 12: many requests in a row on one connection
--- config
    sflow on;
    location = /t {
        return 200 'served';
    }
--- pipelined_requests eval
["GET /t", "GET /t", "GET /t", "GET /t", "GET /t"]
--- response_body eval
["served", "served", "served", "served", "served"]
--- no_error_log
[alert]
[emerg]

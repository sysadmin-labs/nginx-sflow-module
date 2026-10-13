# vi:ft=perl
#
# A configuration that cannot mean anything is refused while it is read, not
# at the first request.  Before this module was taken over, "sflow" accepted
# any word it did not recognise and understood it as "on", so a typo turned
# sampling on and said nothing about it.

use Test::Nginx::Socket 'no_plan';

repeat_each(2);

run_tests();

__DATA__

=== TEST 1: a word that is neither on nor off
--- config
    sflow banana;
    location = /t {
        return 200 'served';
    }
--- must_die
--- error_log
invalid value "banana" in "sflow", "on" or "off" expected



=== TEST 2: on with something after it
--- config
    sflow on please;
    location = /t {
        return 200 'served';
    }
--- must_die
--- error_log
invalid number of arguments in "sflow" directive



=== TEST 3: off with something after it
--- config
    sflow off now;
    location = /t {
        return 200 'served';
    }
--- must_die
--- error_log
invalid number of arguments in "sflow" directive



=== TEST 4: sflow without an argument
--- config
    sflow;
    location = /t {
        return 200 'served';
    }
--- must_die
--- error_log
invalid number of arguments in "sflow" directive



=== TEST 5: sflow_config_file belongs in the http block
--- config
    sflow_config_file /tmp/hsflowd.auto;
    location = /t {
        return 200 'served';
    }
--- must_die
--- error_log
"sflow_config_file" directive is not allowed here



=== TEST 6: sflow_config_file without a path
--- http_config
    sflow_config_file;
--- config
    location = /t {
        return 200 'served';
    }
--- must_die
--- error_log
invalid number of arguments in "sflow_config_file" directive



=== TEST 7: sflow_config_file twice
# One file per server, and the second line would quietly win over the first.
--- http_config
    sflow_config_file /tmp/one.auto;
    sflow_config_file /tmp/two.auto;
--- config
    location = /t {
        return 200 'served';
    }
--- must_die
--- error_log
"sflow_config_file" directive is duplicate

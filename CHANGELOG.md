# Changelog

Newest first.  Dates are release dates.

## Unreleased

### Fixed

- The locking that `--with-threads` used to switch on could never have
  worked: `sfwb_init()` passed `sm->mut`, an `ngx_thread_mutex_t *` that
  nothing ever allocated, to `ngx_thread_mutex_create()`, which expects a
  pointer to a mutex it may initialise.  The whole threaded path is gone
  rather than repaired.  A sample is taken in the worker, in the log phase
  of a request, and nothing else touches that structure: what
  `--with-threads` buys an nginx today is a pool of threads for aio, not a
  request handled by several of them.

- `sflow` accepted any word it did not recognise and understood it as `on`,
  so `sflow of;` turned sampling on and said nothing.  Now it takes `on` or
  `off` and refuses the rest while the configuration is read.

- `sflow on` in a location could not override `sflow off` further out.  The
  flag had two states, so "nothing said here" and "off" looked the same to
  the merge, which then inherited the outer `off` either way.  It has three
  states now and merges with `ngx_conf_merge_value()`.

- `EAI_NODATA` is named only where it exists.  It is gone from FreeBSD, and
  on glibc it is a deprecated synonym for `EAI_NONAME`, which the same
  switch already handles -- so the case label it had was both unportable and
  redundant.  The FreeBSD port carried a patch for exactly this; it does not
  need to any more.

### Added

- `sflow_config_file <path>`, in the http block.  The agent used to read
  `/etc/hsflowd.auto` and nothing else, which made it untestable without
  root and unpackageable without a patch: the FreeBSD port rewrote that
  string with the package prefix.  The compile-time default is still there
  and can still be set with `-DSFWB_DEFAULT_CONFIGFILE=...`, and a
  configuration can now name a file of its own.  The path is copied into
  the shared memory segment rather than pointed at, because the string the
  directive parsed lives in the configuration pool and a reload keeps the
  segment while that pool goes away.

- `ci/datagrams.sh` and a workflow of its own, which is the only check here
  that looks at the product of this module.  It starts a collector, makes
  requests, and decodes what arrives: the version 5 header and the agent
  address, the flow sample and its sampling rate, the HTTP record with
  method, status, URI and user agent, the socket record with both ends, and
  the counters block.  The decoder is written against `src/ngx_http_sflow.h`
  and the encoder in `src/ngx_http_sflow_api.c`, so it says what this module
  emits rather than what some other sFlow agent does.

- `t/` with two files, for the half that does not need a collector: which
  configurations are accepted, which are refused and with what message, and
  that requests are served unchanged whatever the method or the status --
  including the case of a configuration file that is not there, where the
  module samples nothing and nothing else happens.

- The reload gate catches a datagram rather than a 200.  This module answers
  nothing over HTTP, so a probe that asks the server would pass a reload
  that had dropped the module entirely.  `ci/reload.conf` therefore runs a
  collector of its own and the probe fires a request and waits for the
  sample.

- The scaffolding the other modules in this organization carry: a version
  and digest pin for every build input, the release matrix, the FreeBSD
  virtual machine, A/UBSan, valgrind, CodeQL, shellcheck and actionlint.

### Changed

- The sources moved into `src/`, which is where every other module in this
  organization keeps them, and `config` learned the loadable-module case it
  never had: it only ever appended to `HTTP_MODULES` and `NGX_ADDON_SRCS`,
  so `--add-dynamic-module` did not work.

- A `LICENSE` that does not depend on a web server staying up.  Upstream's
  was two lines naming a URL; the text that URL serves is now reproduced in
  full, with the date it was retrieved and its digest, and the two terms
  worth reading before using this are named: acceptance follows from use,
  and the grant is subject to InMon's termination rights.  The scaffolding
  added here is BSD 2-Clause and says so separately.

### Removed

- `README`, whose installation section and sflowtool examples are in
  `README.md` now, and whose first two lines were the licence.

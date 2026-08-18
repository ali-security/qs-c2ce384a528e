#!/bin/bash
# Run the test suite on node 0.6 — the floor of this package's `engines.node`.
#
# No prebuilt 0.6.x linux-x64 binary has ever existed on nodejs.org (or any
# mirror; nvm's own prebuilt support starts at 0.8.6), so 0.6.21 is compiled
# from its source tarball. It must be compiled on CentOS 7: node 0.6's waf
# configure autodetects the SYSTEM OpenSSL and needs SSL_library_init, which
# OpenSSL 1.1 removed, so focal's 1.1.1 fails configure outright; and its
# bundled V8 3.6 segfaults the snapshot builder when compiled by gcc >= 5.
# CentOS 7 carries openssl-devel 1.0.2 and gcc 4.8 together.
set -e

# CentOS 7 is past EOL, so the mirrorlist service no longer resolves; vault
# serves the frozen final repodata.
sed -i 's|^mirrorlist|#mirrorlist|g' /etc/yum.repos.d/CentOS-*.repo
sed -i 's|^#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*.repo
yum install -y -q gcc gcc-c++ make python2 curl openssl-devel

# 0.6's configure shells out to a bare `python` and only parses under python 2.
mkdir -p /opt/shim && ln -sf /usr/bin/python2 /opt/shim/python
export PATH=/opt/shim:$PATH

curl -fsSL https://nodejs.org/dist/v0.6.21/node-v0.6.21.tar.gz | tar xz -C /tmp
cd /tmp/node-v0.6.21
./configure
make -j"$(nproc)"
cp out/Release/node /usr/local/bin/node06

cd /src
node06 --version
# node_modules is installed on the primary node before this container starts:
# npm on 0.6 speaks TLS 1.0 only and cannot reach any registry.
node06 test 2>&1 | tee /tmp/node06-test.log

# The exit status of the suite is unusable on 0.6: tape's exit handler reads the
# code argument of process.on('exit'), which 0.6 does not pass, so it returns
# before applying its own failure code and the run always reports 0. Gate on the
# TAP stream instead.
# `grep -c` exits 1 when the count is zero, which `set -e` would treat as a
# failure of the counting itself; the counts are what the gates below assert on.
ok=$(grep -c '^ok ' /tmp/node06-test.log) || ok=0
not_ok=$(grep -c '^not ok' /tmp/node06-test.log) || not_ok=0
echo "=== node 0.6 TAP summary: ok=${ok} not_ok=${not_ok} ==="
test "${not_ok}" -eq 0
# tape prints its plan footer only after every file has run, so requiring it is
# what distinguishes a completed suite from one an uncaught throw cut short
# (which leaves ok=N/not_ok=0 and would otherwise read as a pass).
grep -qE '^# (fail|pass) ' /tmp/node06-test.log
plan=$(grep -oE '^1\.\.[0-9]+' /tmp/node06-test.log | tail -1 | cut -d. -f3)
echo "=== node 0.6 plan=${plan} ran=${ok} ==="
test "${ok}" -eq "${plan}"

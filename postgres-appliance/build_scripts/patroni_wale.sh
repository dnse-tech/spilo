#!/bin/bash

## -------------------------
## Install patroni and wal-e
## -------------------------

export DEBIAN_FRONTEND=noninteractive

set -ex

ARCH="$(dpkg --print-architecture)"

BUILD_PACKAGES=(python3-pip python3-wheel python3-dev git patchutils binutils gcc)

# On s390x, cryptography (pulled in by wal-e[google]) has no installable wheel,
# so pip builds it from source via maturin. cryptography bootstraps its own
# modern Rust toolchain when none is on PATH, so we deliberately do NOT install
# the (too old, lockfile-v3-only) apt cargo/rustc here — only the OpenSSL/FFI
# headers and pkg-config its native build links against. Purged again at the end.
if [ "$ARCH" = "s390x" ]; then
    BUILD_PACKAGES+=(pkg-config libssl-dev libffi-dev)
fi

apt-get update

# install most of the patroni dependencies from ubuntu packages
apt-cache depends patroni \
        | sed -n -e 's/.* Depends: \(python3-.\+\)$/\1/p' \
        | grep -Ev '^python3-(sphinx|etcd|consul|kazoo|kubernetes)' \
        | xargs apt-get install -y "${BUILD_PACKAGES[@]}" python3-pystache python3-requests

pip3 install setuptools

# maturin is the build backend for cryptography's source build on s390x; install
# it (and ensure cargo is on PATH) before any package that triggers that build.
if [ "$ARCH" = "s390x" ]; then
    pip3 install maturin
fi

if [ "$DEMO" != "true" ]; then
    EXTRAS=",etcd,consul,zookeeper,aws"
    apt-get install -y \
        python3-etcd \
        python3-consul \
        python3-kazoo \
        python3-boto \
        python3-boto3 \
        python3-botocore \
        python3-cachetools \
        python3-cffi \
        python3-gevent \
        python3-pyasn1-modules \
        python3-rsa \
        python3-s3transfer \
        python3-swiftclient

    find /usr/share/python-babel-localedata/locale-data -type f ! -name 'en_US*.dat' -delete

    pip3 install filechunkio protobuf \
            'git+https://github.com/zalando-pg/wal-e.git#egg=wal-e[aws,google,swift]' \
            'git+https://github.com/zalando/pg_view.git@master#egg=pg-view'

    # https://github.com/wal-e/wal-e/issues/318
    sed -i 's/^\(    for i in range(0,\) num_retries):.*/\1 100):/g' /usr/lib/python3/dist-packages/boto/utils.py
else
    EXTRAS=""
fi

pip3 install "patroni[kubernetes$EXTRAS]==$PATRONIVERSION"

for d in /usr/local/lib/python3.10 /usr/lib/python3; do
    cd $d/dist-packages
    find . -type d -name tests -print0 | xargs -0 rm -fr
    find . -type f -name 'test_*.py*' -delete
done
find . -type f -name 'unittest_*.py*' -delete
find . -type f -name '*_test.py' -delete
find . -type f -name '*_test.cpython*.pyc' -delete

# Clean up
apt-get purge -y "${BUILD_PACKAGES[@]}"
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/* \
        /var/cache/debconf/* \
        /root/.cache \
        /usr/share/doc \
        /usr/share/man \
        /usr/share/locale/?? \
        /usr/share/locale/??_?? \
        /usr/share/info
find /var/log -type f -exec truncate --size 0 {} \;

#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

echo -e 'APT::Install-Recommends "0";\nAPT::Install-Suggests "0";' > /etc/apt/apt.conf.d/01norecommend

apt-get update
apt-get -y upgrade
apt-get install -y curl ca-certificates less locales jq vim-tiny gnupg1 cron runit dumb-init libcap2-bin rsync sysstat gpg

ln -s chpst /usr/bin/envdir

# Make it possible to use the following utilities without root (if container runs without "no-new-privileges:true")
setcap 'cap_sys_nice+ep' /usr/bin/chrt
setcap 'cap_sys_nice+ep' /usr/bin/renice

# Disable unwanted cron jobs
rm -fr /etc/cron.??*
truncate --size 0 /etc/crontab

if [ "$DEMO" != "true" ]; then
    # Required for wal-e
    apt-get install -y pv lzop
    # install etcdctl
    ETCDVERSION=3.3.27
    curl -L https://github.com/coreos/etcd/releases/download/v${ETCDVERSION}/etcd-v${ETCDVERSION}-linux-"$(dpkg --print-architecture)".tar.gz \
                | tar xz -C /bin --strip=1 --wildcards --no-anchored --no-same-owner etcdctl etcd
fi

# Dirty hack for smooth migration of existing dbs
bash /builddeps/locales.sh
mv /usr/lib/locale/locale-archive /usr/lib/locale/locale-archive.22
ln -s /run/locale-archive /usr/lib/locale/locale-archive
ln -s /usr/lib/locale/locale-archive.22 /run/locale-archive

# Add PGDG repositories
ARCH="$(dpkg --print-architecture)"
DISTRIB_CODENAME=$(sed -n 's/DISTRIB_CODENAME=//p' /etc/lsb-release)
if [ "$ARCH" = "s390x" ]; then
    # PGDG has no live s390x suite; use the archive (frozen but available for s390x)
    for t in deb deb-src; do
        echo "$t https://apt-archive.postgresql.org/pub/repos/apt/ ${DISTRIB_CODENAME}-pgdg-archive main" >> /etc/apt/sources.list.d/pgdg.list
    done
else
    for t in deb deb-src; do
        echo "$t http://apt.postgresql.org/pub/repos/apt/ ${DISTRIB_CODENAME}-pgdg main" >> /etc/apt/sources.list.d/pgdg.list
    done
fi
curl -s -o - https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg

# PGDG ships no s390x JIT packages; install our pre-built postgresql-NN-jit debs so the
# postgresql-NN-jit-llvm dependency can be satisfied during the binary install step.
if [ "$ARCH" = "s390x" ] && [ -d /builddeps/packages/s390x ]; then
    apt-get update
    apt-get install -y libllvm15
    dpkg -i /builddeps/packages/s390x/postgresql-*-jit_*.deb || true
fi

# add TimescaleDB repository (packagecloud ships amd64/arm64 only; s390x has no
# TimescaleDB packages, so skip the apt repo there)
if [ "$ARCH" != "s390x" ]; then
    echo "deb [signed-by=/etc/apt/keyrings/timescale_timescaledb-archive-keyring.gpg] https://packagecloud.io/timescale/timescaledb/ubuntu/ ${DISTRIB_CODENAME} main" | tee /etc/apt/sources.list.d/timescaledb.list
    curl -fsSL https://packagecloud.io/timescale/timescaledb/gpgkey | gpg --dearmor | tee /etc/apt/keyrings/timescale_timescaledb-archive-keyring.gpg > /dev/null
fi

# Clean up
apt-get purge -y libcap2-bin
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/* \
            /var/cache/debconf/* \
            /usr/share/doc \
            /usr/share/man \
            /usr/share/locale/?? \
            /usr/share/locale/??_??
find /var/log -type f -exec truncate --size 0 {} \;

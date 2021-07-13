FROM centos:7

ARG VERSION
ARG UID=1000
ARG GID=100

ADD etc/yum.repos.d/ /etc/yum.repos.d/

RUN groupadd -r -o -g $GID irods && \
  useradd -r -o -c 'iRODS Administrator' -d /var/lib/irods -s /bin/bash -u $UID -g irods irods

RUN yum install -y epel-release && \
    yum install -y centos-release-scl && \
    yum clean all && \
    rm -rf /var/cache/yum /tmp/*

RUN yum install -y \
        unixODBC \
        supervisor \
        gettext \
        jq \
        haproxy \
        python-pip \
        python-enum \
        libexif-devel \
        libxml2-devel \
        samtools-htslib \
        crontabs \
        mailx \
        nc \
        lnav \
    && \
    yum clean all && \
    rm -rf /var/cache/yum /tmp/*

#RUN yum install -y \
#        irods-server-${VERSION} \
#        irods-runtime-${VERSION} \
#        irods-icommands-${VERSION} \
#        irods-database-plugin-mysql-${VERSION} \
#        irods-rule-engine-plugin-python-${VERSION}.0 \
#        irods-devel-${VERSION} \
#        irods-rule-engine-plugin-audit-amqp-${VERSION}.0 \
#    && \
#    yum clean all && \
#    rm -rf /var/cache/yum /tmp/*

RUN yum -y install rabbitmq-server && \
    yum clean all && \
    rm -rf /var/cache/yum /tmp/*

# Use more recent mysql odbc connector
RUN yum localinstall -y https://repo.mysql.com/yum/mysql-connectors-community/el/7/x86_64/mysql-connector-odbc-8.0.25-1.el7.x86_64.rpm && \
    yum clean all && \
    rm -rf /var/cache/yum /tmp/*

# rr
RUN yum localinstall -y https://github.com/rr-debugger/rr/releases/download/5.4.0/rr-5.4.0-Linux-x86_64.rpm && \
    yum clean all && \
    rm -rf /var/cache/yum /tmp/*

# valgrind, gdb
RUN yum -y install devtoolset-10 && \
    yum clean all && \
    rm -rf /var/cache/yum /tmp/*

RUN mkdir -p \
        /opt/rh/devtoolset-10/root/usr/share/gdb/auto-load.bak/usr/lib \
        /opt/rh/devtoolset-10/root/usr/share/gdb/auto-load.bak/usr/lib64 \
        /opt/rh/devtoolset-10/root/usr/share/gdb/python.bak \
    && \
    mv /opt/rh/devtoolset-10/root/usr/share/gdb/auto-load/usr/lib/libstdc++* \
       /opt/rh/devtoolset-10/root/usr/share/gdb/auto-load.bak/usr/lib && \
    mv /opt/rh/devtoolset-10/root/usr/share/gdb/auto-load/usr/lib64/libstdc++* \
       /opt/rh/devtoolset-10/root/usr/share/gdb/auto-load.bak/usr/lib64 && \
    mv /opt/rh/devtoolset-10/root/usr/share/gdb/python/libstdcxx \
       /opt/rh/devtoolset-10/root/usr/share/gdb/python.bak

ADD https://github.com/koutheir/libcxx-pretty-printers/archive/refs/heads/master.tar.gz /tmp/gdb/libcxx-printers.tar.gz
ADD gdb/auto-load-libcxx.py.in /tmp/gdb/
RUN sed 's|@LIBDIR@|/usr/lib|' /tmp/gdb/auto-load-libcxx.py.in > /opt/rh/devtoolset-10/root/usr/share/gdb/auto-load/usr/lib/libcxx.py && \
    sed 's|@LIBDIR@|/usr/lib64|' /tmp/gdb/auto-load-libcxx.py.in > /opt/rh/devtoolset-10/root/usr/share/gdb/auto-load/usr/lib64/libcxx.py && \
    tar -x -C /tmp/gdb -f /tmp/gdb/libcxx-printers.tar.gz && \
    mv /tmp/gdb/libcxx-pretty-printers-master/src/libcxx \
       /opt/rh/devtoolset-10/root/usr/share/gdb/python && \
    rm -rf /tmp/gdb
ADD https://raw.githubusercontent.com/llvm/llvm-project/main/libcxx/utils/gdb/libcxx/printers.py /opt/rh/devtoolset-10/root/usr/share/gdb/python/libcxx/
ADD http://www.yolinux.com/TUTORIALS/src/dbinit_stl_views-1.03.txt /opt/rh/devtoolset-10/root/etc/gdbinit.d/stl-views.gdb
RUN chmod 644 /opt/rh/devtoolset-10/root/usr/share/gdb/python/libcxx/printers.py && \
    chmod 644 /opt/rh/devtoolset-10/root/etc/gdbinit.d/stl-views.gdb

# lldb
RUN yum -y install llvm-toolset-7 && \
    yum clean all && \
    rm -rf /var/cache/yum /tmp/*

# externals (headers for debugging)
RUN yum -y install 'irods-externals*' && \
    yum clean all && \
    rm -rf /var/cache/yum /tmp/*

ADD packages/irods-devel-*.rpm /irods_packages/
ADD packages/irods-icommands-*.rpm /irods_packages/
ADD packages/irods-runtime-*.rpm /irods_packages/
ADD packages/irods-server-*.rpm /irods_packages/
ADD packages/irods-database-plugin-mysql-*.rpm /irods_packages/
ADD packages/irods-rule-engine-plugin-audit-amqp-*.rpm /irods_packages/
#ADD packages/irods-rule-engine-plugin-python-*.rpm /irods_packages/
RUN yum localinstall -y /irods_packages/*.rpm && \
    rm -rf /irods_packages && \
    yum clean all && \
    rm -rf /var/cache/yum /tmp/*

# utilities
RUN yum install -y \
        nano \
        which \
        lsof \
        less \
    && \
    yum clean all && \
    rm -rf /var/cache/yum /tmp/*

ADD etc/ /etc/
ADD bin/ /usr/local/bin/
ADD irods/server_config.json.tmpl /etc/irods/
ADD irods/irods_environment.json.tmpl /etc/irods/

RUN apply-patches

ENTRYPOINT ["/usr/local/bin/docker-entrypoint"]

ENV SERVER=irods.network.local \
    ZONE=zone_name \
    ADMIN_USER=rods \
    ADMIN_PASS=hunter2 \
    SRV_NEGOTIATION_KEY= \
    SRV_ZONE_KEY= \
    CTRL_PLANE_KEY= \
    SRV_PORT=1247 \
    SRV_PORT_RANGE_START=20000 \
    SRV_PORT_RANGE_END=20199 \
    DB_NAME= \
    DB_USER= \
    DB_PASSWORD= \
    DB_SRV_HOST=mysql.network.local \
    DB_SRV_PORT=3306 \
    DEFAULT_VAULT_DIR=/vault \
    SSL_CERTIFICATE_CHAIN_FILE= \
    SSL_CERTIFICATE_KEY_FILE= \
    SSL_CA_BUNDLE= \
    RE_RULEBASE_SET="rules-local core" \
    PYTHON_RULESETS="rules_local" \
    AMQP=ANONYMOUS@localhost:5672 \
    DEFAULT_RESOURCE=default

# Irods port
EXPOSE 1247

# Control plane port - only to be used with consumers
EXPOSE 1248
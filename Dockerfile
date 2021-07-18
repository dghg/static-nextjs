# Use the official lightweight Node.js 12 image.
# https://hub.docker.com/_/node
FROM node:12-slim as builder

# Create and change to the app directory.
WORKDIR /usr/src/app

# Copy application dependency manifests to the container image.
# A wildcard is used to ensure both package.json AND package-lock.json are copied.
# Copying this separately prevents re-running npm install on every code change.
COPY package*.json ./

# Install dependencies.
RUN npm install

# Copy local code to the container image.
COPY . ./

# Build next js
RUN npm run export

# export
FROM nginx:1.20.1 as build

ARG MODSEC_VERSION=3.0.5

RUN apt-get update \
     && apt-get install -y --no-install-recommends \
     automake \
     cmake \
     doxygen \
     g++ \
     git \
     libcurl4-gnutls-dev \
     libgeoip-dev \
     liblua5.3-dev \
     libpcre++-dev \
     libtool \
     libxml2-dev \
     make \
     ruby \
     wget \
     zlib1g-dev \
     && apt-get clean \
     && rm -rf /var/lib/apt/lists/*

WORKDIR /sources

RUN git clone https://github.com/LMDB/lmdb --branch LMDB_0.9.23 --depth 1 \
     && make -C lmdb/libraries/liblmdb install

RUN git clone https://github.com/lloyd/yajl --branch 2.1.0 --depth 1 \
     && cd yajl \
     && ./configure \
     && make install

RUN wget --quiet https://github.com/ssdeep-project/ssdeep/releases/download/release-2.14.1/ssdeep-2.14.1.tar.gz \
     && tar -xvzf ssdeep-2.14.1.tar.gz \
     && cd ssdeep-2.14.1 \
     && ./configure \
     && make install

RUN git clone https://github.com/SpiderLabs/ModSecurity --branch v${MODSEC_VERSION} --depth 1 \
     && cd ModSecurity \
     && ./build.sh \
     && git submodule init \
     && git submodule update \
     && ./configure --with-yajl=/sources/yajl/build/yajl-2.1.0/ \
     && make install

ARG NGINX_VERSION="1.20.1"
# We use master
RUN git clone -b master --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git \
     && wget --quiet http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz \
     && tar -xzf nginx-${NGINX_VERSION}.tar.gz \
     && cd ./nginx-${NGINX_VERSION} \
     && ./configure --with-compat --add-dynamic-module=../ModSecurity-nginx \
     && make modules \
     && cp objs/ngx_http_modsecurity_module.so /etc/nginx/modules/ \
     && mkdir /etc/modsecurity.d \
     && wget --quiet https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/modsecurity.conf-recommended \
     -O /etc/modsecurity.d/modsecurity.conf \
     && wget --quiet https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/unicode.mapping \
     -O /etc/modsecurity.d/unicode.mapping

FROM nginx:1.20.1

ARG MODSEC_VERSION=3.0.5

LABEL maintainer="Felipe Zipitria <felipe.zipitria@owasp.org>"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV ACCESSLOG=/var/log/nginx/access.log \
     BACKEND=http://localhost:80 \
     DNS_SERVER= \
     ERRORLOG=/var/log/nginx/error.log \
     LOGLEVEL=warn \
     METRICS_ALLOW_FROM='127.0.0.0/24' \
     METRICS_DENY_FROM='all' \
     METRICSLOG=/dev/null \
     MODSEC_AUDIT_ENGINE="RelevantOnly" \
     MODSEC_AUDIT_LOG_FORMAT=JSON \
     MODSEC_AUDIT_LOG_TYPE=Serial \
     MODSEC_AUDIT_LOG=/dev/stdout \
     MODSEC_AUDIT_LOG_PARTS='ABIJDEFHZ' \
     MODSEC_AUDIT_STORAGE=/var/log/modsecurity/audit/ \
     MODSEC_DATA_DIR=/tmp/modsecurity/data \
     MODSEC_DEBUG_LOG=/dev/null \
     MODSEC_DEBUG_LOGLEVEL=0 \
     MODSEC_PCRE_MATCH_LIMIT_RECURSION=100000 \
     MODSEC_PCRE_MATCH_LIMIT=100000 \
     MODSEC_REQ_BODY_ACCESS=on \
     MODSEC_REQ_BODY_LIMIT=13107200 \
     MODSEC_REQ_BODY_NOFILES_LIMIT=131072 \
     MODSEC_RESP_BODY_ACCESS=on \
     MODSEC_RESP_BODY_LIMIT=1048576 \
     MODSEC_RESP_BODY_MIMETYPE="text/plain text/html text/xml" \
     MODSEC_RULE_ENGINE=on \
     MODSEC_TAG=modsecurity \
     MODSEC_TMP_DIR=/tmp/modsecurity/tmp \
     MODSEC_TMP_SAVE_UPLOADED_FILES="on" \
     MODSEC_UPLOAD_DIR=/tmp/modsecurity/upload \
     PORT=80 \
     PROXY_TIMEOUT=60s \
     PROXY_SSL_CERT_KEY=/etc/nginx/conf/server.key \
     PROXY_SSL_CERT=/etc/nginx/conf/server.crt \
     PROXY_SSL_VERIFY=off \
     SERVER_NAME=localhost \
     SSL_PORT=443 \
     TIMEOUT=60s \
     WORKER_CONNECTIONS=1024 \
     LD_LIBRARY_PATH=/lib:/usr/lib:/usr/local/lib

RUN apt-get update \
     && apt-get install -y --no-install-recommends \
     ca-certificates \
     libcurl4-gnutls-dev \
     liblua5.3 \
     libxml2 \
     moreutils \
     && rm -rf /var/lib/apt/lists/* \
     && apt-get clean \
     && mkdir /etc/nginx/ssl

COPY --from=build /usr/local/modsecurity/ /usr/local/modsecurity/
COPY --from=build /usr/local/lib/ /usr/local/lib/
COPY --from=build /etc/nginx/modules/ngx_http_modsecurity_module.so /etc/nginx/modules/ngx_http_modsecurity_module.so
COPY --from=build /etc/modsecurity.d/unicode.mapping /etc/modsecurity.d/unicode.mapping
COPY --from=build /etc/modsecurity.d/modsecurity.conf /etc/modsecurity.d/modsecurity.conf

RUN chgrp -R 0 /var/cache/nginx/ /var/log/ /var/run/ /usr/share/nginx/ /etc/nginx/ /etc/modsecurity.d/ \
     && chmod -R g=u /var/cache/nginx/ /var/log/ /var/run/ /usr/share/nginx/ /etc/nginx/ /etc/modsecurity.d/

COPY --from=builder /usr/src/app/out /www/example

WORKDIR /www/example

COPY ./config/nginx.conf /etc/nginx/nginx.conf
COPY ./config/default.conf /etc/nginx/conf.d/default.conf
COPY ./config/cert.crt /etc/nginx/ssl/server.crt
COPY ./config/cert.key /etc/nginx/ssl/server.key
COPY ./config/modsec/*.conf /etc/modsecurity.d/

EXPOSE 80 443

CMD ["nginx", "-g", "daemon off;"]

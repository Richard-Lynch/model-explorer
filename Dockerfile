# SPDX-License-Identifier: GPL-3.0-or-later
#
# Two stages: node builds the Vite bundle, nginx serves it. The runtime image carries no node and
# no source, only the built files and the nginx config. Both base images are pinned by DIGEST (the
# tag is for the reader and for Renovate), so a rebuild of the same commit uses the same bases.
#
# The catalogue snapshot is NOT in the image: it is the deployment's data. Mount the DIRECTORY
# holding it read-only at /srv/catalogue (nginx serves /srv/catalogue/catalogue.json as
# /catalogue.json), so refreshing it needs no new image. A directory, not the file: a file-level
# bind mount pins the inode, so a snapshot replaced by an atomic rename would never be seen.

FROM node:22-alpine@sha256:fe4f6d74e20370acb04ad889077d14d0f64a9c8ea6a42bc60cddf1e844699914 AS build
WORKDIR /app
COPY package.json package-lock.json ./
# --ignore-scripts: no dependency's install hook runs during the build.
RUN npm ci --ignore-scripts --no-audit --no-fund
COPY tsconfig.json tsconfig.node.json vite.config.ts index.html ./
COPY public ./public
COPY src ./src
RUN npm run build

FROM nginxinc/nginx-unprivileged:1.29.3-alpine@sha256:5aea7cc516b419e3526f47dd1531be31a56a046cfe44754d94f9383e13e2ee99
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY security-headers.conf /etc/nginx/security-headers.conf
COPY --from=build /app/dist /usr/share/nginx/html
# The config is checked when the image is built, so a broken one never reaches a release.
RUN nginx -t
EXPOSE 8080
# Probes 127.0.0.1, not `localhost`: BusyBox wget may resolve localhost to ::1 first, and nginx
# listens on IPv4 only, so a `localhost` probe can fail against a server that is working. It asks
# for the app's own index.html, so a root that serves nothing (403/404) is unhealthy.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/index.html || exit 1

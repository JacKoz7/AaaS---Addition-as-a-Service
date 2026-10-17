# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       successor
# Module:          couchdb/Dockerfile
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Image of the successor's CouchDB (`successor-db`): the
#                  official CouchDB image with the AaaS configuration copied
#                  in. A bind mount is not used because the image's entry
#                  point changes the owner of its configuration files, which
#                  fails on a read-only mount and would change the owner of
#                  the file on a Linux host otherwise.
# Related Docs:    services/successor/couchdb/10-aaas.ini, ADR-0016

FROM couchdb:3.5.1

LABEL org.opencontainers.image.title="successor-db" \
      org.opencontainers.image.description="AaaS successor call log database (CouchDB 3.5.1, single node)." \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/JacKoz7/AaaS---Addition-as-a-Service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="AaaS Contributors" \
      com.aaas.owning-team="Arithmetic Excellence Center (AEC)"

COPY --chown=couchdb:couchdb 10-aaas.ini /opt/couchdb/etc/local.d/10-aaas.ini

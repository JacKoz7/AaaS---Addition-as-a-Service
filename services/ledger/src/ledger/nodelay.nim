# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       ledger
# Module:          ledger/nodelay
# Owning Team:     Transaction Integrity Office (TIO)
# Classification:  INTERNAL
# Purpose:         Disables Nagle's algorithm on the connection of a
#                  std/httpclient client.
# Related Docs:    ADR-0017, services/ledger/docs/CAPACITY.md

## TCP_NODELAY for `std/httpclient`.
##
## **Description:** `std/httpclient` writes the request headers and the
## body with two `send` calls. With Nagle's algorithm on, the body waits
## for the acknowledgement of the headers, which the server delays (Linux
## delayed ACK, 40 ms): every POST then takes about 50 ms instead of 2 ms
## (measured against the successor, ADR-0017). The client does not expose
## its socket, so `std/importutils.privateAccess` is used to reach it and
## set `TCP_NODELAY`. The client opens the socket during the first request
## of a connection, so the option applies from the second request on; a
## replaced socket (a reconnection) is detected and configured again.
##
## **Business Justification:** An addition of 99 999 successor calls takes
## minutes instead of more than an hour.
##
## **Thread Safety:** not thread-safe; event loop only.
##
## **Owner:** Transaction Integrity Office (TIO).
##
## **Since:** ledger 0.1.0

import std/[asyncnet, httpclient, importutils, nativesockets, net]

type NoDelayState* = object
  ## Which socket of a client already has `TCP_NODELAY`.
  ##
  ## **Description:** Compared with the client's current socket.
  ##
  ## **Business Justification:** The option is set once per connection.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  configured: AsyncSocket ## The socket configured last, or nil.

proc applyNoDelay*(client: AsyncHttpClient, state: var NoDelayState) =
  ## Sets `TCP_NODELAY` on the client's socket if it is new.
  ##
  ## **Description:** Call after each completed request. Does nothing
  ## before the first request (no socket) or for a configured socket.
  ##
  ## **Business Justification:** See the module documentation.
  ##
  ## **Parameters:**
  ## - `client`: the HTTP client.
  ## - `state`: its configuration state.
  ##
  ## **Returns:** nothing.
  ##
  ## **Errors:** `OSError` if the option cannot be set (a closed socket).
  ##
  ## **Side Effects:** one `setsockopt` per new connection.
  ##
  ## **Complexity:** O(1).
  ##
  ## **Thread Safety:** not thread-safe.
  ##
  ## **Owner:** Transaction Integrity Office (TIO).
  ##
  ## **Since:** ledger 0.1.0
  ##
  ## **Example:** `discard await (await client.request(url)).body;
  ## client.applyNoDelay(state)`.
  privateAccess(AsyncHttpClient)
  let socket = client.socket
  if socket.isNil or socket == state.configured or socket.isClosed:
    return
  socket.setSockOpt(OptNoDelay, true, level = IPPROTO_TCP.cint)
  state.configured = socket

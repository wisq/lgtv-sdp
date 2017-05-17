# lgtv-sdp

A quick Sinatra app that serves as a dummy server for my LG TV.

## Why?

I bought a 2016 LG 4k OLED TV.

LG decided I should see ads on my home menu screen.

This is unacceptable behaviour for a high-end television.

### Why not block them?

To start with, I tried just blocking them.  I blackholed all LG domains at the DNS level:

* `*.lgtvsdp.com`
* `*.lge.com`
* `*.lgsmartad.com`
* `*.lgappstv.com`

Unfortunately, this had some unanticipated side effects:

* Network connection tests always returned "not connected".
* Automatic time sync was disabled.

(It also disabled the LG Content Store, but that wasn't unanticipated, and I consider it acceptable collateral.)

So I decided to watch the TV's traffic and see if I could mimic the LG servers.

## What does this do?

When my TV boots up, particularly after a power outage, it makes an HTTPS `POST` request to `https://ca.lgtvsdp.com/rest/sdp/v7.0/initservices`.  This provides some basic info about available services, as well as a timestamp.

Note that this HTTPS request actually does not do any certificate checking at all.  That's actually not possible at this point, since the TV is not sure what time it is, and thus can't accurately judge TLS certificate validity.

There are three key aspects of the reply, insofar as fixing the above problems:

* The fact that it gets a reply at all seems to satisfy the network checker.
* Disabling some of the services (setting them to `off`) eliminates some clutter in the "home" menu.
* The `X-Server-Time` HTTP response header is used for time sync.

As such, this app just sends back a (modified) static version of the original response it used to get from LG, along with a dynamic `X-Server-Time` header.

## How do I set it up?

### 1: Point DNS to an IP you control

This will depend on how your network is set up.

In my case, I use PowerDNS as a recursing caching resolver for my home network, and TinyDNS as an authoritative server for local domains.

PowerDNS listens on my LAN address (`192.168.68.1`) and primary loopback address (`127.0.0.1`), and TinyDNS listens on an alternate loopback address (`127.0.0.2`).

* In `/etc/powerdns/recursor.conf`: 
  * `local-address=127.0.0.1,192.168.68.1`
  * `forward-zones-file=/etc/powerdns/forward.conf`
* In `/etc/powerdns/forward.conf`:
  * `lgtvsdp.com=127.0.0.2`
  * `lge.com=127.0.0.2`
  * `lgsmartad.com=127.0.0.2`
  * `lgappstv.com=127.0.0.2`
* Contents of `/etc/sv/tinydns/env/IP`: `127.0.0.2`
* In `/etc/sv/tinydns/root/data`:
  * `+*.lgtvsdp.com:192.168.68.1`
  * `+*.lge.com:192.168.68.1`
  * `+*.lgsmartad.com:192.168.68.1`
  * `+*.lgappstv.com:192.168.68.1`

The net effect is that all DNS for any host in any LG-related domain will point back at my home server, where I can set up servers to handle them.

### 2: Set up an HTTPS server

I use `nginx` as my web server.  The setup is pretty simple:

```
server {
        listen 80;
        listen 443 ssl;
        server_name *.lgtvsdp.com
                    *.lge.com
                    *.lgsmartad.com
                    *.lgappstv.com;

        ssl_certificate     /path/to/a/cert.pem;
        ssl_certificate_key /path/to/a/key.pem;

        location / {
                proxy_pass http://127.0.0.1:3005;
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
        }
}
```

This accepts any requests on standard HTTP/S ports and forwards them to the Sinatra app, which will be listening locally via plain HTTP on port 3005.

### 3: Set up this app

* `bundle install`
* `bundle exec thin start -a 127.0.0.1 -p 3005`

That's about it.  You may want to set this up e.g. as a `runit` service:

```sh
#!/bin/sh

exec 2>&1
set -e -x
cd /path/to/lgtv-sdp
exec chpst -u nobody -- bundle exec thin start -a 127.0.0.1 -p 3005
```

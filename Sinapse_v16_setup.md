Sinapse Frappe v16 – Complete Installation & Setup Guide

1. Purpose

This document records the working installation and recovery setup used for the Sinapse Frappe v16 environment on Windows with Podman + Podman Compose.

The setup is intended for local learning and development of:

Frappe Framework v16

ERPNext v16

Frappe Healthcare v16

Payments

Print Designer

Custom Sinapse/Healthcare navigation and UI changes

The environment uses an existing Frappe site named:

sinapse.localhost

The local browser URL is:

http://sinapse.localhost:8080

The setup deliberately reuses persistent Podman volumes so that the existing site and database are not recreated.

2. Environment

Host OS

Windows + PowerShell

Project directory

F:\Sinapse\sinapse-frappe-v16

Podman

Example environment used during setup:

podman version 6.0.2
podman-compose version 1.6.0

Podman machine

The Podman machine must be running before starting the stack.

Check:

podman machine list

Start it when necessary:

podman machine start

3. Important Safety Rules

The following volumes contain persistent data and must not be deleted during normal recovery:

sinapse_sites
sinapse_db-data

Never use the following for routine troubleshooting:

podman volume rm sinapse_sites
podman volume rm sinapse_db-data
podman volume prune
podman system prune --volumes
podman compose down -v

down -v and volume deletion can remove the data required by the existing Frappe site.

The site/database were preserved during this setup by reusing the existing persistent volumes.

4. Expected Architecture

The final architecture is:

Windows
   |
   | http://sinapse.localhost:8080
   v
+--------------------------+
| Frappe Frontend / Nginx  |
| container :8080          |
+-------------+------------+
              |
              +--------------------+
              |                    |
              v                    v
      +---------------+     +---------------+
      | Frappe        |     | WebSocket      |
      | Backend :8000 |     | :9000          |
      +-------+-------+     +-------+-------+
              |                     |
              v                     v
        +-----------+        +-----------+
        | MariaDB   |        | Redis     |
        | :3306     |        | Queue     |
        +-----------+        +-----------+

Compose service names used by the stack:

backend
frontend
websocket
scheduler
queue-short
queue-long
configurator
db
redis-cache
redis-queue

5. Verify Podman Before Installation

From PowerShell:

podman --version
podman-compose --version
podman machine list
podman info

Confirm that the Podman machine is running.

Example:

podman version 6.0.2
podman-compose version 1.6.0

6. Project Directory

Move to the project:

cd F:\Sinapse\sinapse-frappe-v16

Check the available files:

Get-ChildItem

Important files for this setup include:

compose.yaml
.env

7. Environment Variables

Create or edit:

F:\Sinapse\sinapse-frappe-v16\.env

The important values are:

DB_HOST=db
DB_PORT=3306
REDIS_CACHE=redis-cache:6379
REDIS_QUEUE=redis-queue:6379

These values are important because the Frappe configurator writes Redis settings into the shared site configuration.

If these are empty:

DB_HOST=""
DB_PORT=""
REDIS_CACHE=""
REDIS_QUEUE=""

the WebSocket service can fall back to localhost and fail with an error similar to:

ECONNREFUSED 127.0.0.1:6379

For this setup, use the Compose service names instead:

redis-cache:6379
redis-queue:6379

8. Persistent Volumes

The existing site volume:

sinapse_sites

The existing database volume:

sinapse_db-data

Verify both:

podman volume inspect sinapse_sites --format "{{.Name}}"
podman volume inspect sinapse_db-data --format "{{.Name}}"

Expected:

sinapse_sites
sinapse_db-data

Verify that the site exists inside the site volume:

podman run --rm `
  -v sinapse_sites:/sites `
  localhost/sinapse:16 `
  bash -lc "ls -la /sites && ls -la /sites/sinapse.localhost"

The important directory is:

/sites/sinapse.localhost

with:

site_config.json

9. Final compose.yaml

The final compose configuration for this setup is shown below.

x-customizable-image: &customizable_image
  image: ${CUSTOM_IMAGE:-frappe/erpnext}:${CUSTOM_TAG:-$ERPNEXT_VERSION}
  pull_policy: ${PULL_POLICY:-always}
  restart: ${RESTART_POLICY:-unless-stopped}

x-depends-on-configurator: &depends_on_configurator
  depends_on:
    configurator:
      condition: service_completed_successfully

x-backend-defaults: &backend_defaults
  <<: [*depends_on_configurator, *customizable_image]
  volumes:
    - sites:/home/frappe/frappe-bench/sites

services:

  configurator:
    <<: *backend_defaults
    platform: linux/amd64

    entrypoint:
      - bash
      - -c

    command:
      - >
        ls -1 apps > sites/apps.txt;
        bench set-config -g db_host $$DB_HOST;
        bench set-config -gp db_port $$DB_PORT;
        bench set-config -g redis_cache "redis://$$REDIS_CACHE";
        bench set-config -g redis_queue "redis://$$REDIS_QUEUE";
        bench set-config -g redis_socketio "redis://$$REDIS_QUEUE";
        bench set-config -gp socketio_port $$SOCKETIO_PORT;
        bench set-config -g chromium_path /usr/bin/chromium-headless-shell;

    environment:
      DB_HOST: ${DB_HOST:-db}
      DB_PORT: ${DB_PORT:-3306}
      REDIS_CACHE: ${REDIS_CACHE:-redis-cache:6379}
      REDIS_QUEUE: ${REDIS_QUEUE:-redis-queue:6379}
      SOCKETIO_PORT: "9000"

    depends_on: {}
    restart: on-failure

  backend:
    <<: *backend_defaults
    platform: linux/amd64

    environment:
      GUNICORN_THREADS: ${GUNICORN_THREADS:-4}
      GUNICORN_WORKERS: ${GUNICORN_WORKERS:-2}
      GUNICORN_TIMEOUT: ${GUNICORN_TIMEOUT:-120}

  frontend:
    <<: *customizable_image
    platform: linux/amd64

    ports:
      - "8080:8080"

    command:
      - nginx-entrypoint.sh

    environment:
      BACKEND: backend:8000
      SOCKETIO: websocket:9000
      FRAPPE_SITE_NAME_HEADER: ${FRAPPE_SITE_NAME_HEADER:-$$host}
      UPSTREAM_REAL_IP_ADDRESS: ${UPSTREAM_REAL_IP_ADDRESS:-127.0.0.1}
      UPSTREAM_REAL_IP_HEADER: ${UPSTREAM_REAL_IP_HEADER:-X-Forwarded-For}
      UPSTREAM_REAL_IP_RECURSIVE: ${UPSTREAM_REAL_IP_RECURSIVE:-off}
      PROXY_READ_TIMEOUT: ${PROXY_READ_TIMEOUT:-120}
      CLIENT_MAX_BODY_SIZE: ${CLIENT_MAX_BODY_SIZE:-50m}

    volumes:
      - sites:/home/frappe/frappe-bench/sites

    depends_on:
      - backend
      - websocket

  websocket:
    <<: [*depends_on_configurator, *customizable_image]
    platform: linux/amd64

    command:
      - node
      - /home/frappe/frappe-bench/apps/frappe/socketio.js

    volumes:
      - sites:/home/frappe/frappe-bench/sites

  queue-short:
    <<: *backend_defaults
    platform: linux/amd64

    command:
      - bench
      - worker
      - --queue
      - short,default

  queue-long:
    <<: *backend_defaults
    platform: linux/amd64

    command:
      - bench
      - worker
      - --queue
      - long,default,short

  scheduler:
    <<: *backend_defaults
    platform: linux/amd64

    command:
      - bench
      - schedule

  db:
    image: mariadb:11.8
    restart: unless-stopped

    command:
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci
      - --skip-character-set-client-handshake

    environment:
      MYSQL_ROOT_PASSWORD: "123"
      MARIADB_AUTO_UPGRADE: "1"

    healthcheck:
      test:
        - CMD
        - healthcheck.sh
        - --connect
        - --innodb_initialized
      interval: 5s
      timeout: 5s
      retries: 20

    volumes:
      - db-data:/var/lib/mysql

  redis-cache:
    image: redis:8.6-alpine
    restart: unless-stopped

  redis-queue:
    image: redis:8.6-alpine
    restart: unless-stopped

    volumes:
      - redis-queue-data:/data

volumes:
  sites:
    external: true
    name: sinapse_sites

  db-data:
    external: true
    name: sinapse_db-data

  redis-queue-data:

Important compose details

Frontend port

The Frappe nginx configuration in this environment listens internally on:

8080

Therefore the correct port mapping is:

ports:
  - "8080:8080"

Using:

- "8080:80"

is incorrect for this image/configuration.

Existing sites volume

The site volume must point to:

sinapse_sites

not a newly created project volume such as:

sinapse-frappe-v16_sites

If the wrong volume is mounted, the backend shows:

No sites found

and the frontend can return:

sinapse.localhost does not exist

10. Starting the Stack

From:

cd F:\Sinapse\sinapse-frappe-v16

Start the stack:

podman-compose up -d

Check the containers:

podman ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

Expected services:

sinapse-frappe-v16_db_1
sinapse-frappe-v16_redis-cache_1
sinapse-frappe-v16_redis-queue_1
sinapse-frappe-v16_configurator_1
sinapse-frappe-v16_backend_1
sinapse-frappe-v16_websocket_1
sinapse-frappe-v16_queue-short_1
sinapse-frappe-v16_queue-long_1
sinapse-frappe-v16_scheduler_1
sinapse-frappe-v16_frontend_1

The configurator normally exits with:

Exited (0)

This is expected because it performs one-time/shared configuration and finishes.

11. Verify the Database

Check database health:

podman ps --filter "name=sinapse-frappe-v16_db_1"

A healthy result should show:

Up ... (healthy)

12. Verify Redis

Check Redis containers:

podman ps --filter "name=sinapse-frappe-v16_redis"

Expected:

redis-cache  Up
redis-queue  Up

Optional ping tests:

podman exec sinapse-frappe-v16_redis-cache_1 redis-cli ping
podman exec sinapse-frappe-v16_redis-queue_1 redis-cli ping

Expected:

PONG
PONG

13. Verify the Frappe Site

Run:

podman exec sinapse-frappe-v16_backend_1 bash -lc "cd /home/frappe/frappe-bench && bench list-sites"

Expected:

Available sites:
  sinapse.localhost

Then:

podman exec sinapse-frappe-v16_backend_1 bash -lc "cd /home/frappe/frappe-bench && bench --site sinapse.localhost list-apps"

The exact installed apps depend on the image/site state. In this environment the available application namespace included:

frappe
erpnext
healthcare
print_designer
payments

14. Verify the Frontend Port

Run:

podman port sinapse-frappe-v16_frontend_1

Expected:

8080/tcp -> 0.0.0.0:8080

Also:

podman inspect sinapse-frappe-v16_frontend_1 --format "{{json .NetworkSettings.Ports}}"

The output must not be:

{}

15. Verify Nginx is Listening on 8080

Inside the frontend:

podman exec sinapse-frappe-v16_frontend_1 bash -lc "ss -lntp"

Expected:

LISTEN ... 0.0.0.0:8080 ... nginx

Check nginx configuration:

podman exec sinapse-frappe-v16_frontend_1 nginx -t

Expected:

syntax is ok
test is successful

16. Verify WebSocket

Check:

podman logs sinapse-frappe-v16_websocket_1 --tail 50

Expected:

Realtime service listening on: ws://0.0.0.0:9000

A previous failure mode was:

ECONNREFUSED 127.0.0.1:6379

This happened because Redis variables were empty in .env, causing the Socket.IO process to attempt Redis on localhost.

The corrected .env values are:

REDIS_CACHE=redis-cache:6379
REDIS_QUEUE=redis-queue:6379

17. Open the Site

Use the actual Frappe site hostname:

http://sinapse.localhost:8080

The generic:

http://localhost:8080

may not resolve the desired site because Frappe uses the HTTP Host header for site routing.

18. If You Get sinapse.localhost does not exist

Check the backend first:

podman exec sinapse-frappe-v16_backend_1 bash -lc "cd /home/frappe/frappe-bench && bench list-sites"

If you get:

No sites found

inspect the mounted sites directory:

podman exec sinapse-frappe-v16_backend_1 bash -lc "ls -la /home/frappe/frappe-bench/sites"

There should be:

sinapse.localhost

If it is missing, verify that the service uses the persistent volume:

podman inspect sinapse-frappe-v16_backend_1 --format "{{json .Mounts}}"

The destination must be:

/home/frappe/frappe-bench/sites

and the volume should resolve to:

sinapse_sites

19. If You Get ERR_EMPTY_RESPONSE

First check the port:

podman port sinapse-frappe-v16_frontend_1

Then confirm the internal nginx port:

podman exec sinapse-frappe-v16_frontend_1 bash -lc "ss -lntp"

For this setup nginx listens on:

8080

Therefore the correct mapping is:

- "8080:8080"

Not:

- "8080:80"

20. If WebSocket Exits with Redis Errors

Check:

podman logs sinapse-frappe-v16_websocket_1 --tail 100

If you see:

ECONNREFUSED 127.0.0.1:6379

check .env:

Get-Content .\.env | Select-String "DB_HOST|DB_PORT|REDIS_CACHE|REDIS_QUEUE"

Required:

DB_HOST=db
DB_PORT=3306
REDIS_CACHE=redis-cache:6379
REDIS_QUEUE=redis-queue:6379

Then rerun the compose stack:

podman-compose up -d

21. If Compose Tries to Remove Missing Containers

You may see messages such as:

no container with name or ID "sinapse-frappe-v16_frontend_1" found

or:

queue-short_1 not found

This indicates the Compose project's container state is inconsistent.

First inspect:

podman ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

Do not immediately delete the persistent volumes.

Usually the safer recovery is:

podman-compose up -d

rather than repeatedly using --force-recreate on a partially inconsistent Podman project.

22. Daily Start After Windows Shutdown

When Windows is restarted, Podman may not automatically have the machine available.

Start Podman:

podman machine start

Go to the project:

cd F:\Sinapse\sinapse-frappe-v16

Start the application:

podman-compose up -d

Check:

podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

Then open:

http://sinapse.localhost:8080

23. Stop the Environment

To stop the application containers without intentionally deleting persistent data:

cd F:\Sinapse\sinapse-frappe-v16
podman-compose down

Do not add -v during normal shutdown.

24. Recommended Start/Stop Scripts

start-sinapse.ps1

Create:

F:\Sinapse\sinapse-frappe-v16\start-sinapse.ps1

Content:

Write-Host "========================================"
Write-Host " Starting Sinapse Frappe v16"
Write-Host "========================================"

Set-Location "F:\Sinapse\sinapse-frappe-v16"

$machine = podman machine list --format "{{.Name}} {{.Running}}"

if ($machine -notmatch "true") {
    Write-Host "Starting Podman machine..."
    podman machine start
}

Write-Host "Starting Frappe containers..."
podman-compose up -d

Write-Host "Waiting for services..."
Start-Sleep -Seconds 10

Write-Host ""
Write-Host "Container status:"
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

Write-Host ""
Write-Host "Open: http://sinapse.localhost:8080"

Run:

cd F:\Sinapse\sinapse-frappe-v16
.\start-sinapse.ps1

If PowerShell blocks local scripts:

Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

Then run the script again.

stop-sinapse.ps1

Set-Location "F:\Sinapse\sinapse-frappe-v16"
podman-compose down
Write-Host "Sinapse stopped. Persistent volumes were not intentionally removed."

25. Frappe Console

Open the Frappe console:

podman exec -it sinapse-frappe-v16_backend_1 bash -lc "cd /home/frappe/frappe-bench && bench --site sinapse.localhost console"

Example:

frappe.get_hooks("app_title")

Exit:

exit()

26. Healthcare App Verification

Inside the container, verify the app source:

podman exec sinapse-frappe-v16_backend_1 bash -lc "head -20 /home/frappe/frappe-bench/apps/healthcare/healthcare/hooks.py"

The Healthcare app title was customized during development to:

app_title = "Selvi Hospital"

This is a source-level customization and is separate from the site/company data.

27. Healthcare Desktop Navigation Customization

Healthcare Desktop Icon source files are under:

/home/frappe/frappe-bench/apps/healthcare/healthcare/desktop_icon/

For example:

healthcare.json
insurance.json
rehabilitation.json
inpatient.json
diagnostics.json
setup.json
outpatient.json

During the customization work, their parent_icon values were changed from the old branding label to:

Selvi Hospital

This controls the Desktop navigation hierarchy.

28. Home Navigation Customization

The desired navigation design is:

Home
  -> Healthcare

Reception
  -> Reception workspace

Outpatient
  -> Outpatient workspace

Inpatient
  -> Inpatient workspace

Nurse
  -> Nurse workspace

Practitioner
  -> Practitioner workspace

Lab
  -> Lab workspace

Pharmacy
  -> Pharmacy workspace

Reception is intended to contain patient-registration workflows such as:

New Patient
Patient Visit Entry
Patient Encounter

Reports
  Patient Registration Report
  Patient Entry Report
  Patient Summary

The Patient/Reception workflow should remain separate from the top-level Home navigation.

29. Patient Mobile Number Masking

A UI masking test was performed for the Patient List.

Desired presentation:

9842783315

becomes:

984278****

The database value should remain unchanged.

The Frappe list data test confirmed that the formatting function can generate the masked value correctly.

Example browser-side formatter:

frappe.listview_settings["Patient"] = {
    add_fields: ["mobile"],

    formatters: {
        mobile(value) {
            if (!value) return "";

            value = String(value).trim();

            if (value.length <= 4) {
                return "****";
            }

            return value.substring(0, value.length - 4) + "****";
        }
    }
};

The important privacy rule is:

Database: 9842783315
UI:       984278****

Do not overwrite the database value merely to mask it visually.

30. Troubleshooting Commands

Container status

podman ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

Frontend logs

podman logs sinapse-frappe-v16_frontend_1 --tail 100

Backend logs

podman logs sinapse-frappe-v16_backend_1 --tail 100

WebSocket logs

podman logs sinapse-frappe-v16_websocket_1 --tail 100

Database logs

podman logs sinapse-frappe-v16_db_1 --tail 100

Frontend port

podman port sinapse-frappe-v16_frontend_1

Nginx configuration

podman exec sinapse-frappe-v16_frontend_1 nginx -t

Nginx listening port

podman exec sinapse-frappe-v16_frontend_1 bash -lc "ss -lntp"

Frappe site list

podman exec sinapse-frappe-v16_backend_1 bash -lc "cd /home/frappe/frappe-bench && bench list-sites"

Installed apps

podman exec sinapse-frappe-v16_backend_1 bash -lc "cd /home/frappe/frappe-bench && bench --site sinapse.localhost list-apps"

31. Common Failure Modes and Root Causes

A. localhost refused to connect

Likely cause:

frontend container is not running

Check:

podman ps -a

Also check:

podman port sinapse-frappe-v16_frontend_1

B. ERR_EMPTY_RESPONSE

In this setup this was caused by mapping:

8080:80

while nginx actually listened on:

8080

Correct mapping:

8080:8080

C. sinapse.localhost does not exist

Usually means the current container is mounted to an empty/different site volume.

Check:

podman exec sinapse-frappe-v16_backend_1 bash -lc "cd /home/frappe/frappe-bench && bench list-sites"

If it says:

No sites found

verify the sites volume is mapped to:

sinapse_sites

D. ECONNREFUSED 127.0.0.1:6379

The WebSocket process is trying to use Redis on itself.

Correct configuration:

REDIS_CACHE=redis-cache:6379
REDIS_QUEUE=redis-queue:6379

E. host not found in upstream

Example:

host not found in upstream "sinapse_websocket:9000"

This means nginx cannot resolve that service name in the container network.

Use Compose service names:

SOCKETIO: websocket:9000
BACKEND: backend:8000

Do not use manually-created container names unless the network is deliberately configured that way.

F. Access denied for user '_2500f9c...'

This occurred when the site's MariaDB user existed for a different host than the current application container.

The site's database credentials are stored in:

sites/sinapse.localhost/site_config.json

Example structure:

{
  "db_name": "...",
  "db_password": "...",
  "db_type": "mariadb",
  "db_user": "..."
}

Do not recreate the site just because of a database-user permission issue. Verify the user/grants in MariaDB first.

32. Clean Recovery Checklist

When the application is not opening, use this order:

Start Podman machine.

Go to F:\Sinapse\sinapse-frappe-v16.

Check .env.

Check sinapse_sites and sinapse_db-data volumes.

Run podman-compose up -d.

Check DB health.

Check Redis.

Check bench list-sites.

Check WebSocket logs.

Check frontend port 8080:8080.

Open http://sinapse.localhost:8080.

Only after these checks consider deeper fixes.

Do not start by deleting containers/volumes.

33. Recommended Daily Workflow

Morning / system start

podman machine start
cd F:\Sinapse\sinapse-frappe-v16
podman-compose up -d

Verify

podman ps

Open

http://sinapse.localhost:8080

End of day

cd F:\Sinapse\sinapse-frappe-v16
podman-compose down

Persistent volumes remain available for the next startup.

34. Final Validation Checklist

Before considering the installation complete, verify all of the following:

[ ] Podman machine is running
[ ] .env contains DB_HOST=db
[ ] .env contains DB_PORT=3306
[ ] .env contains REDIS_CACHE=redis-cache:6379
[ ] .env contains REDIS_QUEUE=redis-queue:6379
[ ] sinapse_sites volume exists
[ ] sinapse_db-data volume exists
[ ] sinapse.localhost exists in the sites volume
[ ] MariaDB is healthy
[ ] Redis cache is running
[ ] Redis queue is running
[ ] backend is running
[ ] websocket is running
[ ] queue-short is running
[ ] queue-long is running
[ ] scheduler is running
[ ] frontend is running
[ ] frontend exposes 0.0.0.0:8080->8080/tcp
[ ] nginx listens on 8080 inside frontend
[ ] bench list-sites shows sinapse.localhost
[ ] Healthcare site opens at http://sinapse.localhost:8080

35. Known Environment-Specific Notes

Node.js inside backend

A bench build --app healthcare attempt failed in this runtime because the backend container did not have node in its PATH:

node: not found

Therefore, do not assume bench build is available from the backend runtime container. Build operations should be performed from an image/runtime that includes Node.js, or by using the project’s appropriate asset-build workflow.

Configurator

A configurator container exiting with:

Exited (0)

is normal.

Podman compose provider

podman compose may report that it is using the external podman-compose provider. This is expected in the environment where podman-compose is installed separately.

36. Summary

The stable local Sinapse Frappe v16 configuration is:

Project:
F:\Sinapse\sinapse-frappe-v16

Site:
sinapse.localhost

Browser:
http://sinapse.localhost:8080

Frontend:
8080 -> 8080

Image:
localhost/sinapse:16

Sites volume:
sinapse_sites

Database volume:
sinapse_db-data

Database host:
db

Redis cache:
redis-cache:6379

Redis queue:
redis-queue:6379

The key principle for this environment is:

Preserve persistent volumes
        +
Use the correct Compose service names
        +
Use the correct frontend internal port (8080)
        +
Keep Redis configuration consistent
        +
Verify sinapse.localhost exists before troubleshooting UI

This keeps the existing Sinapse site/data available while allowing continued Frappe Healthcare development and learning.
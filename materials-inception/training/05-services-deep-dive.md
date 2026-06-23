# Lab 05 — MariaDB, WordPress, NGINX: What Each Service Does

> **Goal:** Understand each of the 3 project services well enough to configure them from scratch.
> Time: ~1 hour (read + practice)

---

## Service 1 — MariaDB

### What MariaDB is

MariaDB is a relational database — it stores structured data in tables with rows and columns.
It's a drop-in replacement for MySQL (same protocol, same client commands).

WordPress uses it to store: posts, users, settings, comments, plugins — everything.

### How MariaDB starts up

```
1. mysql_install_db   → creates system tables (mysql.user, mysql.tables, etc.)
2. mysqld --start     → daemon starts, reads config from /etc/mysql/
3. listens on port 3306 for MySQL protocol connections
4. authenticates with username + password
5. serves queries on databases it manages
```

### Key config options (mariadb.cnf)

```ini
[mysqld]
datadir       = /var/lib/mysql    # where databases are stored on disk
socket        = /var/run/mysqld/mysqld.sock  # Unix socket for local connections
bind-address  = 0.0.0.0          # accept connections from any IP
port          = 3306
user          = mysql             # run as this OS user
```

**Why `bind-address = 0.0.0.0`?**
Default is `127.0.0.1` — only local connections. WordPress runs in a different container,
so it connects over the Docker network. MariaDB must accept that.

### SQL you need to know

```sql
-- List all databases
SHOW DATABASES;

-- Create a database
CREATE DATABASE mydb;

-- Create a user (% means from any host, not just localhost)
CREATE USER 'wp_user'@'%' IDENTIFIED BY 'password';

-- Give full access to a database
GRANT ALL PRIVILEGES ON mydb.* TO 'wp_user'@'%';

-- Set root password
ALTER USER 'root'@'localhost' IDENTIFIED BY 'rootpassword';

-- Apply changes
FLUSH PRIVILEGES;

-- Show who has access to what
SHOW GRANTS FOR 'wp_user'@'%';
```

### Exercise: Explore MariaDB manually

```bash
# Start MariaDB in a container (quick test — NOT the project setup)
docker run -d --name explore-db \
  -e MYSQL_ROOT_PASSWORD=root \
  -e MYSQL_DATABASE=testdb \
  -e MYSQL_USER=testuser \
  -e MYSQL_PASSWORD=testpass \
  mariadb:10.11

sleep 20   # wait for init

# Connect as root
docker exec -it explore-db mariadb -uroot -proot

# Run these queries and understand each result:
SHOW DATABASES;
SELECT user, host, password FROM mysql.user;
SHOW GRANTS FOR 'testuser'@'%';
USE testdb;
CREATE TABLE posts (id INT AUTO_INCREMENT PRIMARY KEY, title VARCHAR(200));
INSERT INTO posts (title) VALUES ('Hello World');
SELECT * FROM posts;

\q

# Cleanup
docker rm -f explore-db
```

---

## Service 2 — WordPress + PHP-FPM

### What PHP-FPM is

PHP-FPM = PHP FastCGI Process Manager.

WordPress is written in PHP. When NGINX receives a request for a `.php` file, it doesn't execute PHP itself — it forwards the request to PHP-FPM via the **FastCGI protocol**, waits for the response, and sends it back to the browser.

```
Browser → NGINX (HTTP/HTTPS) → PHP-FPM (FastCGI:9000) → PHP code executes → response
                                    ↕
                                MariaDB:3306
```

### FastCGI vs HTTP

```
HTTP:      NGINX acts as a server, WordPress speaks HTTP back
FastCGI:   NGINX acts as a proxy, WordPress speaks FastCGI back

FastCGI is a binary protocol — faster than HTTP for local communication
PHP-FPM listens on port 9000 (or a Unix socket)
NGINX talks to it with fastcgi_pass directive
```

### PHP-FPM pool config (www.conf)

```ini
[www]
; Listen on port 9000 for FastCGI connections
listen = 9000

; Accept connections from NGINX (by IP or any with 0.0.0.0)
listen.allowed_clients = 0.0.0.0

; Process management: how many PHP workers to run
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
```

### WP-CLI — WordPress command line tool

WP-CLI lets you manage WordPress without a browser:

```bash
# Download WordPress
wp core download --path=/var/www/html --allow-root

# Create wp-config.php
wp config create \
  --dbname=wordpress \
  --dbuser=wp_user \
  --dbpass=password \
  --dbhost=mariadb \
  --path=/var/www/html \
  --allow-root

# Install WordPress (creates database tables, sets up admin)
wp core install \
  --url=https://akuzmin.42.fr \
  --title="My Site" \
  --admin_user=wp_admin \
  --admin_password=adminpass \
  --admin_email=admin@example.com \
  --path=/var/www/html \
  --allow-root

# Create a second (regular) user
wp user create wp_user user@example.com \
  --role=author \
  --user_pass=userpass \
  --path=/var/www/html \
  --allow-root
```

### Exercise: Understand the WordPress setup flow

Think through this sequence and explain each step to yourself:

1. WordPress container starts
2. Init script checks if `/var/www/html/wp-config.php` exists
3. If NO (first run): downloads WordPress via WP-CLI
4. Creates wp-config.php (tells WordPress how to connect to MariaDB)
5. Runs WordPress installer (creates tables in MariaDB)
6. Creates admin user (username cannot contain "admin/administrator")
7. Creates regular user
8. `exec php-fpm8.2 -F` — PHP-FPM becomes PID 1

**Question:** Why does step 2 check for `wp-config.php` specifically?

Because WP-CLI creates it as the last step of configuration. If it exists, WordPress is already set up.

---

## Service 3 — NGINX

### What NGINX does in this project

NGINX has two jobs:
1. **TLS termination**: decrypt HTTPS from the browser
2. **Reverse proxy**: forward PHP requests to WordPress/PHP-FPM

```
Browser (HTTPS:443)
    ↓ TLS decryption
NGINX
    ├── Static files (CSS, JS, images) → served directly from WordPress volume
    └── PHP files → forwarded to PHP-FPM:9000 via FastCGI
```

### TLS/SSL basics

```
HTTPS = HTTP + TLS encryption

TLS requires:
  1. Private key (.key) — kept secret, used to decrypt
  2. Certificate (.crt) — public, sent to browser to prove identity
  
Certificate contains:
  - Your public key
  - Domain name it's valid for
  - Who signed it (Certificate Authority, or self-signed)
  - Expiry date
```

**Self-signed certificate** (what we use):
```bash
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/nginx.key \
  -out /etc/nginx/ssl/nginx.crt \
  -subj "/CN=akuzmin.42.fr"
```

Browsers will show a "not secure" warning because no real CA signed it. That's fine for 42.

### NGINX config for WordPress (nginx.conf)

```nginx
server {
    listen 443 ssl;
    server_name akuzmin.42.fr;

    # TLS configuration
    ssl_certificate     /etc/nginx/ssl/nginx.crt;
    ssl_certificate_key /etc/nginx/ssl/nginx.key;
    ssl_protocols       TLSv1.2 TLSv1.3;   # only these two versions

    root  /var/www/html;      # WordPress files (shared volume)
    index index.php;

    # Try the URL as a file, then directory, then route through WordPress
    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    # Send PHP files to PHP-FPM
    location ~ \.php$ {
        include        fastcgi_params;
        fastcgi_pass   wordpress:9000;        # container name: port
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
}
```

**Why `wordpress:9000`?** Docker's custom network resolves `wordpress` to the WordPress container's IP automatically.

### TLSv1.2 vs TLSv1.3

The subject requires ONLY these two versions:
```nginx
ssl_protocols TLSv1.2 TLSv1.3;
```

- TLS 1.0 and 1.1 are deprecated and insecure
- TLS 1.2 is still widely used (supported by all modern browsers)
- TLS 1.3 is faster and more secure (fewer roundtrips to establish connection)

### Exercise: Understand the NGINX config

Read the nginx.conf above and explain each block:
1. What does `listen 443 ssl` mean?
2. What is `ssl_protocols` restricting?
3. What does `try_files $uri $uri/ /index.php?$args` do?
4. What does `fastcgi_pass wordpress:9000` do?
5. What is `SCRIPT_FILENAME` used for?

---

## The Full Request Flow (learn this by heart)

```
1. Browser requests https://akuzmin.42.fr/wp-admin/

2. /etc/hosts resolves akuzmin.42.fr → VM IP

3. TCP connection to VM:443

4. NGINX accepts the connection
   - TLS handshake (sends certificate, negotiates TLSv1.3)
   - Browser sees self-signed cert, shows warning (accept it)

5. NGINX receives: GET /wp-admin/ HTTP/1.1

6. try_files: /wp-admin/ doesn't exist as a file or dir
   → falls through to /index.php?$args

7. location ~ \.php$ matches
   → fastcgi_pass wordpress:9000
   → FastCGI request sent to WordPress container on port 9000

8. WordPress container receives FastCGI request
   PHP-FPM worker executes index.php

9. WordPress PHP code runs:
   - Connects to mariadb:3306 (using wp-config.php credentials)
   - Queries database for the requested page/post
   - Generates HTML

10. PHP-FPM sends FastCGI response to NGINX

11. NGINX sends HTTP response to browser over the TLS connection

12. Browser displays the WordPress admin page
```

---

## Knowledge Check

1. What protocol does NGINX use to communicate with PHP-FPM?
2. Why is PHP-FPM in a SEPARATE container from NGINX?
3. What does `wp-config.php` contain?
4. What is a self-signed certificate? Why does the browser warn about it?
5. What TLS versions must Inception use? Why are 1.0 and 1.1 excluded?
6. What does `try_files $uri $uri/ /index.php?$args` do?
7. Why does the WordPress admin username not contain "admin"?
8. What port does PHP-FPM listen on by default?
9. Walk through the complete request flow from browser to MariaDB and back.

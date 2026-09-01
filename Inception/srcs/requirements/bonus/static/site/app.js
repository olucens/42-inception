// Renders the service cards from one source of truth, so the list cannot drift
// out of sync between markup and prose.
var SERVICES = [
  { name: "nginx",     port: ":443",  core: true,  desc: "TLS 1.2/1.3 termination. The only entry point into the stack." },
  { name: "wordpress", port: ":9000", core: true,  desc: "PHP-FPM only — no web server. Speaks FastCGI to NGINX." },
  { name: "mariadb",   port: ":3306", core: true,  desc: "The database. No published port; reachable only from WordPress." },
  { name: "redis",     port: ":6379", core: false, desc: "Persistent object cache. allkeys-lru eviction, no persistence." },
  { name: "ftp",       port: ":21",   core: false, desc: "vsftpd onto the WordPress volume, chrooted to the site root." },
  { name: "static",    port: ":8080", core: false, desc: "This page. Plain HTML/CSS/JS served by its own NGINX." },
  { name: "adminer",   port: ":8081", core: false, desc: "Web UI for inspecting the database during a defence." },
  { name: "backup",    port: "cron",  core: false, desc: "Nightly mariadb-dump, gzipped and rotated on its own volume." }
];

var host = document.getElementById("services");
if (host) {
  SERVICES.forEach(function (s) {
    var el = document.createElement("article");
    el.className = "card";
    el.setAttribute("data-core", String(s.core));

    var h = document.createElement("h3");
    h.appendChild(document.createTextNode(s.name));
    var span = document.createElement("span");
    span.className = "port";
    span.textContent = s.port;
    h.appendChild(span);

    var p = document.createElement("p");
    p.textContent = s.desc;

    el.appendChild(h);
    el.appendChild(p);
    host.appendChild(el);
  });
}

var year = document.getElementById("year");
if (year) { year.textContent = new Date().getFullYear(); }

server {
        listen      80 default_server;
        server_name _;
        access_log  off;
        error_log   /dev/null;
	return 301 https://$host$request_uri;
}

server {
	listen              8083 default_server ssl;
	server_name         _;
	root                /usr/local/hestia/web;
	# Fix error "The plain HTTP request was sent to HTTPS port"
	error_page          497 https://$host:$server_port$request_uri;
	error_page          403 /error/404.html;
	error_page          404 /error/404.html;
	error_page          410 /error/410.html;
	error_page          500 501 502 503 504 505 /error/50x.html;

	ssl_certificate     /usr/local/hestia/ssl/certificate.crt;
	ssl_certificate_key /usr/local/hestia/ssl/certificate.key;

	# TLS 1.3 0-RTT anti-replay
	if ($anti_replay = 307) { return 307 https://$host:$server_port$request_uri; }
	if ($anti_replay = 425) { return 425; }

	location / {
		expires off;
		index index.php;
	}

	location /error/ {
		expires off;
		internal;
	}

	location /rrd/ {
		expires off;
		internal;
	}

	location /backup/ {
		root /;
		internal;
	}

	location /fm/ {
		alias /usr/local/hestia/web/fm/dist/;
		index index.php;

		location ~ /([^/]+\.php)$ {
			try_files     /$1 =404;
			include       fastcgi_params;
			fastcgi_param HTTP_EARLY_DATA $rfc_early_data if_not_empty;
			fastcgi_param SCRIPT_FILENAME /usr/local/hestia/web/fm/dist/index.php;
			fastcgi_pass  unix:/run/hestia-php.sock;
			fastcgi_index index.php;
		}
	}

	location ~ \.php$ {
		include                  fastcgi_params;
		fastcgi_param            HTTP_EARLY_DATA $rfc_early_data if_not_empty;
		fastcgi_param            SCRIPT_FILENAME /usr/local/hestia/web/$fastcgi_script_name;
		fastcgi_pass             unix:/run/hestia-php.sock;
		fastcgi_intercept_errors on;
		break;
	}
}



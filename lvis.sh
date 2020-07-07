#!/bin/bash

# get user input for domain and generate uuid
echo "type domain without \e[1;31mwww\e[0m and perss enter:"
read domain
apt-get update
apt-get --assume-yes upgrade
uuid=$(uuidgen)

# install certificate using acme
apt-get --assume-yes install socat
bash <(curl -L -s https://get.acme.sh)
source ~/.bashrc
~/.acme.sh/acme.sh --issue -d "$domain" --standalone -k ec-256
~/.acme.sh/acme.sh --installcert -d "$domain" --fullchainpath /etc/v2ray/v2ray.crt --keypath /etc/v2ray/v2ray.key --ecc

# install nginx and set default config file
apt-get --assume-yes install nginx
nginx_config=$(cat <<-END
server {
        listen 80 default_server;
        listen [::]:80 default_server;

        root /var/www/html;

        index index.html index.htm index.nginx-debian.html;

        server_name $domain;

        location / {
                try_files \$uri \$uri/ =404;
        }

        location ~ /\.ht {
               deny all;
        }
}

server {
  listen 443 ssl;
  ssl on;
  ssl_certificate       /etc/v2ray/v2ray.crt;
  ssl_certificate_key   /etc/v2ray/v2ray.key;
  ssl_protocols         TLSv1 TLSv1.1 TLSv1.2;
  ssl_ciphers           HIGH:!aNULL:!MD5;
  server_name           $domain;
        location /ray {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;

        # Show realip in v2ray access.log
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }
}
END
)
echo "$nginx_config" > default
mv default /etc/nginx/sites-available/default
nginx -t
/etc/init.d/nginx restart

# install v2ray and its config.json
bash <(curl -L -s https://install.direct/go.sh)
v2ray_config=$(cat <<-END
{
  "inbounds": [
    {
      "port": 10000,
      "listen":"127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "alterId": 64
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
        "path": "/ray"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
END
)
echo "$v2ray_config" > config.json
mv config.json /etc/v2ray/config.json
service v2ray start

# enable bbr
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p
sysctl net.ipv4.tcp_available_congestion_control
lsmod | grep bbr

# firewall settings
ufw app list
ufw allow OpenSSH
ufw allow "Nginx HTTPS"
echo "y" | sudo ufw enable
ufw status

# last piece
echo "Successfully installed v2ray"
echo "uuid:"
echo -e "\e[1;33m$uuid\e[0m"

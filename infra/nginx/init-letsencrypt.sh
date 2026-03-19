#!/bin/bash

# Configuration
domains=(kizuna.ayushanand.in)
rsa_key_size=4096
email="your-email@example.com" # Adding a valid email is highly recommended
staging=0 # Set to 1 if you're testing to avoid hitting request limits

echo "### Creating dummy certificate for $domains ..."
sudo docker compose -f ../../docker-compose.yml -f ../../docker-compose.prod.yml run --rm --entrypoint "\
  sh -c 'mkdir -p /etc/letsencrypt/live/$domains && \
  openssl req -x509 -nodes -newkey rsa:4096 -days 1\
    -keyout /etc/letsencrypt/live/$domains/privkey.pem \
    -out /etc/letsencrypt/live/$domains/fullchain.pem \
    -subj \"/CN=localhost\"'" certbot
echo


echo "### Starting nginx ..."
sudo docker compose -f ../../docker-compose.yml -f ../../docker-compose.prod.yml up --force-recreate -d nginx
echo

echo "### Deleting dummy certificate for $domains ..."
sudo docker compose -f ../../docker-compose.yml -f ../../docker-compose.prod.yml run --rm --entrypoint "\
  sh -c 'rm -rf /etc/letsencrypt/live/$domains && \
  rm -rf /etc/letsencrypt/archive/$domains && \
  rm -rf /etc/letsencrypt/renewal/$domains.conf'" certbot
echo


echo "### Requesting Let's Encrypt certificate for $domains ..."
#Join $domains to -d args
domain_args=""
for domain in "${domains[@]}"; do
  domain_args="$domain_args -d $domain"
done

# Select appropriate email arg
email_arg="--email $email"
if [ -z "$email" ]; then email_arg="--register-unsafely-without-email"; fi

# Enable staging mode if needed
staging_arg=""
if [ "$staging" != "0" ]; then staging_arg="--staging"; fi

sudo docker compose -f ../../docker-compose.yml -f ../../docker-compose.prod.yml run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $staging_arg \
    $email_arg \
    $domain_args \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --force-renewal" certbot
echo

echo "### Reloading nginx ..."
sudo docker compose -f ../../docker-compose.yml -f ../../docker-compose.prod.yml exec nginx nginx -s reload
echo "### Done! Visit https://$domains/health to verify."

#!/usr/bin/env bash
workdir="/var/www"
# Because we can not set up many env variable sin build process, we are going to process here!
# Setting up the production database
echo " # Production DB
production:
  adapter: postgresql
  host: ${POSTGRES_HOST}
  database: ${POSTGRES_DB}
  username: ${POSTGRES_USER}
  password: ${POSTGRES_PASSWORD}
  encoding: utf8" > $workdir/config/database.yml

# Setting up the SERVER_URL and SERVER_PROTOCOL
# Rails is supposed to pick up env with OPENSTREETMAP prefix but for some reason this is not the case
# So we'll just manually override the settings.local.yml for now
sed -i -e 's/server_url: "openstreetmap.example.com"/server_url: "'$OPENSTREETMAP_server_url'"/g' $workdir/config/settings.local.yml
sed -i -e 's/server_protocol: "http"/server_protocol: "'$OPENSTREETMAP_server_protocol'"/g' $workdir/config/settings.local.yml

# # Setting up the email
# sed -i -e 's/openstreetmap@example.com/'$MAILER_SENDER_EMAIL'/g' $workdir/config/settings.local.yml
sed -i -e 's/smtp_address: "localhost"/smtp_address: "'$MAILER_ADDRESS'"/g' $workdir/config/settings.local.yml
sed -i -e 's/smtp_user_name: null/smtp_user_name: "'$MAILER_USERNAME'"/g' $workdir/config/settings.local.yml
sed -i -e 's/smtp_password: null/smtp_password: "'$MAILER_PASSWORD'"/g' $workdir/config/settings.local.yml
sed -i -e 's/smtp_domain: "localhost"/smtp_domain: "'$MAILER_DOMAIN'"/g' $workdir/config/settings.local.yml
sed -i -e 's/email_from: "OpenStreetMap <openstreetmap@example.com>"/email_from: "HOTOSM <'$MAILER_SENDER_EMAIL'>"/g' $workdir/config/settings.local.yml
sed -i -e 's/email_return_path: "openstreetmap@example.com"/email_return_path: "'$MAILER_SENDER_EMAIL'"/g' $workdir/config/settings.local.yml
sed -i -e 's/smtp_authentication: null/smtp_authentication: "plain"/g' $workdir/config/settings.local.yml
sed -i -e 's/smtp_enable_starttls_auto: false/smtp_enable_starttls_auto: true/g' $workdir/config/settings.local.yml
# echo -e "\nsmtp_tls: true" >> $workdir/config/settings.local.yml

sed -i -e 's/support_email: "openstreetmap@example.com"/support_email: "'$MAILER_SENDER_EMAIL'"/g' $workdir/config/settings.local.yml

# # Set up iD key
sed -i -e 's/id-key/'$OPENSTREETMAP_id_key'/g' $workdir/config/settings.local.yml


# Check if DB is already up

flag=true
while "$flag" = true; do
  pg_isready -h $POSTGRES_HOST -p 5432 >/dev/null 2>&2 || continue
  flag=false
  # Print the log while compiling the assets
  # until $(curl -sf -o /dev/null $OPENSTREETMAP_server_url); do
  #     echo "Waiting to start rails ports server..."
  #    sleep 2
  # done &

  # Precompile again, to catch the env variables
  # RAILS_ENV=production rake assets:precompile --trace

  # db:migrate
  bundle exec rails db:migrate

  # Start the delayed jobs queue worker
  nohup bundle exec rake jobs:work &
  # Start the app
  apachectl -k start -DFOREGROUND
done



FROM httpd:2.4-alpine

# Install unzip to unpack the frontend zip bundle
RUN apk add --no-cache unzip curl

# Copy custom Apache HTTPD configuration
COPY httpd.conf /usr/local/apache2/conf/httpd.conf

# Clean default Apache static files
RUN rm -rf /usr/local/apache2/htdocs/*

# Accept frontend artifact zip file
ARG FRONTEND_ARTIFACT=pet-store-frontend.zip
COPY ${FRONTEND_ARTIFACT} /tmp/frontend.zip

# Unpack Angular bundle into htdocs and ensure correct permissions
RUN unzip -q /tmp/frontend.zip -d /usr/local/apache2/htdocs/ \
    && rm /tmp/frontend.zip \
    && chmod -R 755 /usr/local/apache2/htdocs/

EXPOSE 80

CMD ["httpd-foreground"]

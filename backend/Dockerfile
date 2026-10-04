FROM tomcat:11.0-jdk21-temurin

# Install curl for container health check
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

# Remove default Tomcat applications
RUN rm -rf /usr/local/tomcat/webapps/* \
    && rm -rf /usr/local/tomcat/webapps.dist

# Create upload storage directory with full permissions
RUN mkdir -p /uploads && chmod 777 /uploads

# Set standard JVM and container options
ENV CATALINA_OPTS="-XX:+UseG1GC -XX:MaxRAMPercentage=75.0 -Djava.security.egd=file:/dev/./urandom -Dapp.storage.upload-dir=/uploads"

# Copy WAR file as ROOT.war so endpoints are mapped directly to /api/**
ARG WAR_FILE=petstore.war
COPY ${WAR_FILE} /usr/local/tomcat/webapps/ROOT.war

EXPOSE 8080

CMD ["catalina.sh", "run"]

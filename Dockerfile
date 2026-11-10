FROM maven:3.9-eclipse-temurin-25 AS build
ARG APP_VERSION=0.1.0-SNAPSHOT
WORKDIR /build
COPY pom.xml .
COPY src ./src
RUN mvn -B -ntp org.codehaus.mojo:versions-maven-plugin:2.19.1:set \
      -DnewVersion="$APP_VERSION" -DgenerateBackupPoms=false \
    && mvn -B -ntp package -DskipTests

FROM eclipse-temurin:25-jre
LABEL org.opencontainers.image.source="https://github.com/emanuelleda/limitcore" \
      org.opencontainers.image.description="LimitCore - distributed rate limiting API"

# Ubuntu 26.04 base images may still ship vulnerable APT 3.2.0
# (CVE-2026-109518, fixed in 3.2.1ubuntu0.1). Keep download retries
# disabled until the package manager itself has been updated.
RUN apt-get update -o Acquire::Retries=0 \
    && apt-get install -y --no-install-recommends --only-upgrade \
      -o Acquire::Retries=0 apt libapt-pkg7.0 \
    && dpkg --compare-versions "$(dpkg-query -W -f='\${Version}' apt)" ge '3.2.1ubuntu0.1' \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -r -u 10001 app
WORKDIR /app
COPY --from=build --chown=10001:10001 /build/target/limitcore-*.jar /app/app.jar
USER 10001
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError"
EXPOSE 8080
ENTRYPOINT ["java","-jar","/app/app.jar"]

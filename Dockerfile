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

RUN useradd -r -u 10001 app
WORKDIR /app
COPY --from=build --chown=10001:10001 /build/target/limitcore-*.jar /app/app.jar
USER 10001
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError"
EXPOSE 8080
ENTRYPOINT ["java","-jar","/app/app.jar"]

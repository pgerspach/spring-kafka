# Build application
FROM maven:3-jdk-11-openj9 as builder
WORKDIR /home/maven
COPY . .
RUN mvn clean package

# Stage and thin the application
# tag::OLimage1[]
FROM open-liberty as staging
# end::OLimage1[]

# tag::copyJar[]
COPY --from=builder --chown=1001:0 /home/maven/target/spring-kafka-0.1.0.jar \
                    /staging/fat-spring-kafka-0.1.0.jar
# end::copyJar[]

# tag::springBootUtility[]
RUN springBootUtility thin \
 --sourceAppPath=/staging/fat-spring-kafka-0.1.0.jar \
 --targetThinAppPath=/staging/thin-spring-kafka-0.1.0.jar \
 --targetLibCachePath=/staging/lib.index.cache
# end::springBootUtility[]

# Build the image
# tag::OLimage2[]
FROM open-liberty:19.0.0.9-springBoot2-java11
# end::OLimage2[]

ARG VERSION=0.1.0
ARG REVISION=SNAPSHOT

LABEL \
  org.opencontainers.image.authors="Patrick Gerspach" \
  org.opencontainers.image.vendor="Open Liberty" \
  org.opencontainers.image.url="local" \
  org.opencontainers.image.version="$VERSION" \
  org.opencontainers.image.revision="$REVISION" \
  vendor="Open Liberty" \
  name="spring kafka app" \
  version="$VERSION-$REVISION" \
  summary="Spring Kafka app"

# tag::serverXml[]
RUN cp /opt/ol/wlp/templates/servers/springBoot2/server.xml /config/server.xml
# end::serverXml[]

# tag::libcache[]
COPY --chown=1001:0 --from=staging /staging/lib.index.cache /lib.index.cache
# end::libcache[]
# tag::thinjar[]
COPY --chown=1001:0 --from=staging /staging/thin-spring-kafka-0.1.0.jar \
                    /config/dropins/spring/thin-spring-kafka-0.1.0.jar
# end::thinjar[]

RUN configure.sh 


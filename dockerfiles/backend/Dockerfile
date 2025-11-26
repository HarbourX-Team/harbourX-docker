# Multi-stage build for Spring Boot application
FROM maven:3.9-eclipse-temurin-21 AS build
ARG BACKEND_DIR=HarbourX-Backend
WORKDIR /app

# Copy pom.xml and download dependencies (cached layer)
COPY ${BACKEND_DIR}/pom.xml .
RUN mvn dependency:go-offline -B

# Copy source code and build
COPY ${BACKEND_DIR}/src ./src
RUN mvn clean package -DskipTests

# Runtime stage
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

# Install wget for health checks
RUN apk add --no-cache wget

# Create non-root user
RUN addgroup -S spring && adduser -S spring -G spring
USER spring:spring

# Copy the built JAR
COPY --from=build /app/target/*.jar app.jar

# Expose port
EXPOSE 8080

# Health check - use TCP port check as all HTTP endpoints require authentication
# This checks if the port is open and accepting connections
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/ 2>&1 | grep -q "403\|200\|401" || exit 1

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]


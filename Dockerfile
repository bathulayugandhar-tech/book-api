# ---------- Stage 1: build the jar ----------
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app

# Download dependencies first (cached until pom.xml changes)
COPY pom.xml .
RUN mvn -B -q dependency:go-offline

# Compile and package
COPY src ./src
RUN mvn -B -q package -DskipTests

# ---------- Stage 2: run the jar ----------
FROM eclipse-temurin:17-jre
WORKDIR /app

# Non-root user
RUN useradd -r -u 1001 spring
COPY --from=build /app/target/*.jar app.jar
USER spring

EXPOSE 8080
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75"
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]

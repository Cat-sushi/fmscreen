# Use latest stable channel SDK.
FROM dart:stable AS build

# Resolve app dependencies.
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

# Copy app source code (except anything in .dockerignore) and AOT compile app.
COPY . .
RUN dart compile exe bin/server.dart -o bin/server
# RUN dart bin/fetchdl.dart

# Build minimal serving image from AOT-compiled `/server`
# and the pre-built AOT-runtime in the `/runtime/` directory of the base image.
FROM scratch
COPY --from=build /runtime/ /
# COPY --from=build /app /app/
COPY --from=build /app/bin/server /app/bin/
COPY --from=build /app/assets /app/assets/

# Start server.
WORKDIR /app
EXPOSE 8080
CMD ["./bin/server", "-p8080"]

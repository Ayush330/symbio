FROM postgres:15-alpine

# Set environment variables
ENV POSTGRES_DB=symbio_db
ENV POSTGRES_USER=ayush_admin
ENV POSTGRES_PASSWORD=troy_secure_pass

# Now we point to the file relative to the context (infra folder)
COPY postgres/init.sql /docker-entrypoint-initdb.d/
FROM postgrest/postgrest:v12.0.2

# Copy configuration
COPY postgrest.conf /etc/postgrest/postgrest.conf

# JWT secret will be mounted as volume or set via env
# COPY jwt-secret.txt /etc/postgrest/jwt-secret.txt

EXPOSE 3000

CMD ["postgrest", "/etc/postgrest/postgrest.conf"]

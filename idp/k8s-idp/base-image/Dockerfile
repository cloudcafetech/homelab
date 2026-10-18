FROM node:20-alpine

WORKDIR /app

# Create working directory structure and ensure GID 0 write access
RUN mkdir -p /app/src/public /app/db && \
    chown -R 1001:0 /app && \
    chmod -R 775 /app

COPY package*.json ./
RUN npm install --production && \
    chown -R 1001:0 /app/node_modules && \
    chmod -R 775 /app/node_modules

# Use a non-root UID; OpenShift overrides this dynamically anyway
USER 1001:0
ENV NODE_PATH=/app/node_modules

CMD ["node", "/app/src/server.js"]



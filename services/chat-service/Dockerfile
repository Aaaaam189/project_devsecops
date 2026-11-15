FROM node:20-alpine
WORKDIR /app

RUN addgroup -g 10001 -S appgroup && adduser -u 10001 -S appuser -G appgroup

COPY package*.json ./
RUN npm install --omit=dev

COPY . .

RUN chown -R appuser:appgroup /app
USER appuser

EXPOSE 99999

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD ["wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8085/health"]

CMD ["node", "src/server.js"]

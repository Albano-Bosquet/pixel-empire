# Pixel Empire relay. Build: docker build -t pixel-empire-relay tools/relay
# Run:   docker run -d --restart=always -p 8080:8080 pixel-empire-relay
FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY server.js ./
ENV PORT=8080
EXPOSE 8080
USER node
CMD ["node", "server.js"]
